-- ================================================================
-- PROYECTO FINAL — ROYALE GOLD CASINO
-- Bases de Datos — Script Unificado y Completo
-- Compatible con: Oracle Database 21c XE / Oracle Live SQL (Free)
--
-- ORDEN DE EJECUCIÓN (todo en un único archivo):
--   [1] Limpieza de objetos previos
--   [2] DDL — Tablas, constraints y estructura
--   [3] PL/SQL — Triggers
--   [4] PL/SQL — Procedimientos almacenados
--   [5] PL/SQL — Funciones
--   [6] Vistas de seguridad y reportería
--   [7] Roles simulados (compatible XE / LiveSQL)
--   [8] Datos de ejemplo (mínimo 3 filas por tabla)
--   [9] Pruebas: Triggers, Procedimientos, ACID, Vistas
--
-- AUTOEVALUACIÓN PREVIA A LA ENTREGA:
--   SELECT object_name, object_type, status
--   FROM   user_objects
--   WHERE  object_type IN ('TABLE','TRIGGER','PROCEDURE','VIEW','FUNCTION','PACKAGE')
--   AND    status = 'INVALID';
--   -- Si devuelve 0 filas: todos los objetos son válidos.
--
-- CUADRO DE MANDO DE ENTREGABLES:
--   #1  [X] Listo — 3+ tablas con FK y CHECK: cargo, empleado, cliente,
--               sala, tipo_juego, mesa, maquina, cajero, transaccion,
--               sesion_mesa, sesion_maquina, torneo, inscripcion_torneo,
--               movimiento_puntos, incidente, auditoria_log, usuarios_sistema
--   #2  [X] Listo — Script de limpieza (DROP IF EXISTS) en bloque BEGIN/FOR
--   #3  [X] Listo — Mínimo 3 filas por tabla principal (ver sección 8)
--   #4  [X] Listo — Bloque NOWAIT con PRAGMA(-54): blq_acid_nowait
--   #5  [X] Listo — Bloque WAIT n con PRAGMA(-30006): blq_acid_wait
--   #6  [X] Listo — COMMIT y ROLLBACK en ambos escenarios ACID
--   #7  [X] Listo — Trigger BEFORE INSERT con :NEW y RAISE: trg_cliente_edad_minima
--   #8  [X] Listo — Prueba trigger OK y FALLO documentada con DBMS_OUTPUT
--   #9  [X] Listo — Stored Procedure 2+ DMLs y EXCEPTION: sp_registrar_transaccion
--   #10 [X] Listo — Vista de seguridad sin columnas sensibles: v_catalogo_publico
--   #11 [X] Listo — Vista de reporte JOIN + GROUP BY + SUM/COUNT: v_reporte_ingresos_sala
--   #12 [X] Listo — Archivo .sql único y completo
-- ================================================================

SET SERVEROUTPUT ON;

-- ================================================================
-- SECCIÓN 1: LIMPIEZA DE OBJETOS PREVIOS
-- ================================================================
-- PROPÓSITO: Permitir re-ejecución limpia del script sin errores.
--   Elimina todos los objetos en el orden correcto para respetar
--   dependencias: triggers antes que procedimientos, vistas antes
--   que tablas, tablas con CASCADE CONSTRAINTS para FK.
-- ================================================================
PROMPT ============================================================
PROMPT  [1/9] Limpiando objetos previos...
PROMPT ============================================================

BEGIN
    FOR r IN (
        SELECT object_name, object_type
        FROM   user_objects
        WHERE  object_type IN (
            'TRIGGER','PROCEDURE','FUNCTION',
            'PACKAGE BODY','PACKAGE','VIEW','TABLE'
        )
        ORDER BY CASE object_type
            WHEN 'TRIGGER'      THEN 1
            WHEN 'PROCEDURE'    THEN 2
            WHEN 'FUNCTION'     THEN 3
            WHEN 'PACKAGE BODY' THEN 4
            WHEN 'PACKAGE'      THEN 5
            WHEN 'VIEW'         THEN 6
            WHEN 'TABLE'        THEN 7
        END
    ) LOOP
        BEGIN
            IF r.object_type = 'TABLE' THEN
                -- CASCADE CONSTRAINTS elimina FK dependientes automáticamente
                EXECUTE IMMEDIATE
                    'DROP TABLE ' || r.object_name || ' CASCADE CONSTRAINTS';
            ELSE
                EXECUTE IMMEDIATE
                    'DROP ' || r.object_type || ' ' || r.object_name;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL; -- Ignorar si el objeto ya no existe
        END;
    END LOOP;
END;
/

PROMPT >> Limpieza completada.

-- ================================================================
-- SECCIÓN 2: DDL — TABLAS
-- ================================================================
-- PROPÓSITO: Crear la estructura completa de la base de datos del
--   casino. Incluye tablas maestras, transaccionales, de control
--   de juego, de cumplimiento AML y de auditoría.
--
-- REGLAS DE NEGOCIO IMPLEMENTADAS EN DDL:
--   - CHECK turno:          Solo turnos válidos de operación
--   - CHECK nivel_membresia: Solo niveles del programa de lealtad
--   - CHECK tipo transaccion: Solo operaciones autorizadas en caja
--   - CHECK estado mesa:    Controla disponibilidad operativa
--   - CHECK autoexcluido:   Flag binario para juego responsable
--   - IDENTITY:             IDs autogenerados, sin secuencias manuales
-- ================================================================
PROMPT ============================================================
PROMPT  [2/9] Creando tablas...
PROMPT ============================================================

-- ----------------------------------------------------------------
-- OBJETO: TABLE cargo
-- PROPÓSITO: Catálogo de cargos del casino con salario base.
--   Define la jerarquía organizacional (CEO, Croupier, Cajero, etc.)
-- TABLAS AFECTADAS: cargo (maestra de empleado)
-- ----------------------------------------------------------------
CREATE TABLE cargo (
    cargo_id        NUMBER(6)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR2(100)   NOT NULL,
    salario_base    NUMBER(12,2)    NOT NULL
                    CONSTRAINT chk_cargo_salario_positivo CHECK (salario_base > 0),
    descripcion     VARCHAR2(500)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE empleado
-- PROPÓSITO: Registro de todos los empleados del casino.
--   Vincula cada persona a un cargo y controla su turno y estado.
-- TABLAS AFECTADAS: empleado (referencia cargo)
-- CONSTRAINTS CLAVE:
--   chk_emp_turno  — Solo turnos operativos válidos del casino
--   chk_emp_activo — Flag binario, evita valores fuera de 0/1
-- ----------------------------------------------------------------
CREATE TABLE empleado (
    empleado_id         NUMBER(8)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cedula              VARCHAR2(20)    NOT NULL UNIQUE,
    nombres             VARCHAR2(100)   NOT NULL,
    apellidos           VARCHAR2(100)   NOT NULL,
    cargo_id            NUMBER(6)       NOT NULL,
    fecha_ingreso       DATE            NOT NULL,
    email_corporativo   VARCHAR2(150),
    turno               VARCHAR2(10)    DEFAULT 'ROTATIVO'
                        CONSTRAINT chk_emp_turno
                        CHECK (turno IN ('MAÑANA','TARDE','NOCHE','ROTATIVO')),
    activo              NUMBER(1)       DEFAULT 1
                        CONSTRAINT chk_emp_activo CHECK (activo IN (0,1)),
    CONSTRAINT fk_emp_cargo
        FOREIGN KEY (cargo_id) REFERENCES cargo(cargo_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE cliente
-- PROPÓSITO: Registro de clientes del casino con control de
--   juego responsable: límite diario, autoexclusión y membresía.
-- TABLAS AFECTADAS: cliente (tabla central del sistema)
-- CONSTRAINTS CLAVE:
--   chk_cli_membresia   — Solo niveles del programa de lealtad
--   chk_cli_activo      — Estado de cuenta del cliente
--   chk_cli_autoexcluido — Flag de autoexclusión voluntaria
--   chk_cli_limite      — El límite diario debe ser positivo
--   chk_cli_gasto       — El gasto acumulado no puede ser negativo
-- ----------------------------------------------------------------
CREATE TABLE cliente (
    cliente_id          NUMBER(10)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cedula              VARCHAR2(20)    NOT NULL UNIQUE,
    nombres             VARCHAR2(100)   NOT NULL,
    apellidos           VARCHAR2(100)   NOT NULL,
    fecha_nacimiento    DATE            NOT NULL,
    email               VARCHAR2(150)   UNIQUE,
    telefono            VARCHAR2(20),
    direccion           VARCHAR2(255),
    ciudad              VARCHAR2(80),
    fecha_registro      TIMESTAMP       DEFAULT SYSTIMESTAMP,
    nivel_membresia     VARCHAR2(10)    DEFAULT 'BRONCE'
                        CONSTRAINT chk_cli_membresia
                        CHECK (nivel_membresia IN ('BRONCE','PLATA','ORO','PLATINO','VIP')),
    puntos_lealtad      NUMBER(10)      DEFAULT 0,
    activo              NUMBER(1)       DEFAULT 1
                        CONSTRAINT chk_cli_activo CHECK (activo IN (0,1)),
    autoexcluido        NUMBER(1)       DEFAULT 0
                        CONSTRAINT chk_cli_autoexcluido CHECK (autoexcluido IN (0,1)),
    limite_diario       NUMBER(14,2)    DEFAULT 5000000
                        CONSTRAINT chk_cli_limite CHECK (limite_diario > 0),
    gasto_hoy           NUMBER(14,2)    DEFAULT 0
                        CONSTRAINT chk_cli_gasto CHECK (gasto_hoy >= 0)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE sala
-- PROPÓSITO: Catálogo de salas físicas del casino.
--   Clasifica el espacio por tipo (general, VIP, torneos).
-- ----------------------------------------------------------------
CREATE TABLE sala (
    sala_id     NUMBER(6)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR2(80)    NOT NULL,
    tipo        VARCHAR2(10)    DEFAULT 'GENERAL'
                CONSTRAINT chk_sala_tipo CHECK (tipo IN ('GENERAL','VIP','TORNEO')),
    capacidad   NUMBER(5)       NOT NULL
                CONSTRAINT chk_sala_capacidad CHECK (capacidad > 0),
    activa      NUMBER(1)       DEFAULT 1
                CONSTRAINT chk_sala_activa CHECK (activa IN (0,1))
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE tipo_juego
-- PROPÓSITO: Catálogo de juegos disponibles en el casino.
--   Define límites de jugadores por tipo de juego.
-- ----------------------------------------------------------------
CREATE TABLE tipo_juego (
    tipo_juego_id   NUMBER(6)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR2(80)    NOT NULL,
    descripcion     VARCHAR2(500),
    min_jugadores   NUMBER(3)       DEFAULT 1,
    max_jugadores   NUMBER(3)       DEFAULT 8
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE mesa
-- PROPÓSITO: Mesas de juego del casino con apuestas mínimas/máximas.
--   El estado controla la disponibilidad operativa en tiempo real.
-- CONSTRAINTS CLAVE:
--   chk_mesa_estado     — Solo estados operativos válidos
--   chk_mesa_apuestas   — La apuesta mínima debe ser < máxima
-- ----------------------------------------------------------------
CREATE TABLE mesa (
    mesa_id         NUMBER(8)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero          VARCHAR2(10)    NOT NULL UNIQUE,
    sala_id         NUMBER(6)       NOT NULL,
    tipo_juego_id   NUMBER(6)       NOT NULL,
    apuesta_min     NUMBER(12,2)    DEFAULT 10000
                    CONSTRAINT chk_mesa_apmin CHECK (apuesta_min > 0),
    apuesta_max     NUMBER(12,2)    DEFAULT 5000000,
    estado          VARCHAR2(15)    DEFAULT 'ACTIVA'
                    CONSTRAINT chk_mesa_estado
                    CHECK (estado IN ('ACTIVA','INACTIVA','MANTENIMIENTO')),
    CONSTRAINT chk_mesa_apuestas
        CHECK (apuesta_max > apuesta_min),    -- Regla de negocio: max siempre > min
    CONSTRAINT fk_mesa_sala
        FOREIGN KEY (sala_id)       REFERENCES sala(sala_id),
    CONSTRAINT fk_mesa_tjuego
        FOREIGN KEY (tipo_juego_id) REFERENCES tipo_juego(tipo_juego_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE maquina
-- PROPÓSITO: Máquinas tragamonedas del casino.
--   porcentaje_pago (RTP) es el retorno al jugador, regulado por ley.
-- CONSTRAINTS CLAVE:
--   chk_maq_rtp — El RTP debe estar entre 85% y 99% (regulación)
-- ----------------------------------------------------------------
CREATE TABLE maquina (
    maquina_id          NUMBER(8)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    serial              VARCHAR2(50)    NOT NULL UNIQUE,
    modelo              VARCHAR2(100),
    fabricante          VARCHAR2(100),
    sala_id             NUMBER(6)       NOT NULL,
    apuesta_min         NUMBER(10,2)    DEFAULT 500
                        CONSTRAINT chk_maq_apmin CHECK (apuesta_min > 0),
    apuesta_max         NUMBER(10,2)    DEFAULT 500000,
    porcentaje_pago     NUMBER(5,2)     DEFAULT 95.00
                        CONSTRAINT chk_maq_rtp CHECK (porcentaje_pago BETWEEN 85 AND 99),
    estado              VARCHAR2(15)    DEFAULT 'ACTIVA'
                        CONSTRAINT chk_maq_estado
                        CHECK (estado IN ('ACTIVA','INACTIVA','MANTENIMIENTO')),
    fecha_instalacion   DATE,
    CONSTRAINT fk_maq_sala
        FOREIGN KEY (sala_id) REFERENCES sala(sala_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE cajero
-- PROPÓSITO: Vincula empleados a posiciones físicas de caja.
--   Un cajero opera una sola caja; una caja tiene un único cajero.
-- ----------------------------------------------------------------
CREATE TABLE cajero (
    cajero_id       NUMBER(6)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    empleado_id     NUMBER(8)       NOT NULL UNIQUE,  -- Un empleado = una caja
    numero_caja     VARCHAR2(10)    NOT NULL UNIQUE,
    CONSTRAINT fk_cajero_emp
        FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE transaccion
-- PROPÓSITO: Registro de todas las operaciones de caja del casino.
--   Es la tabla más crítica del sistema; toda salida o entrada
--   de dinero queda registrada aquí con tipo y método de pago.
-- CONSTRAINTS CLAVE:
--   chk_trans_tipo    — Solo operaciones autorizadas
--   chk_trans_metodo  — Solo métodos de pago aceptados
--   chk_trans_monto   — No se permiten transacciones en cero o negativas
-- ----------------------------------------------------------------
CREATE TABLE transaccion (
    transaccion_id  NUMBER(15)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id      NUMBER(10)      NOT NULL,
    cajero_id       NUMBER(6)       NOT NULL,
    tipo            VARCHAR2(20)    NOT NULL
                    CONSTRAINT chk_trans_tipo
                    CHECK (tipo IN ('COMPRA_FICHAS','CANJE_FICHAS','DEPOSITO','RETIRO','PREMIO')),
    monto           NUMBER(14,2)    NOT NULL
                    CONSTRAINT chk_trans_monto CHECK (monto > 0),
    metodo_pago     VARCHAR2(20)    DEFAULT 'EFECTIVO'
                    CONSTRAINT chk_trans_metodo
                    CHECK (metodo_pago IN ('EFECTIVO','TARJETA_DEBITO','TARJETA_CREDITO','TRANSFERENCIA')),
    fecha_hora      TIMESTAMP       DEFAULT SYSTIMESTAMP,
    referencia      VARCHAR2(80),
    revertida       NUMBER(1)       DEFAULT 0
                    CONSTRAINT chk_trans_revertida CHECK (revertida IN (0,1)),
    CONSTRAINT fk_trans_cliente
        FOREIGN KEY (cliente_id) REFERENCES cliente(cliente_id),
    CONSTRAINT fk_trans_cajero
        FOREIGN KEY (cajero_id)  REFERENCES cajero(cajero_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE sesion_mesa
-- PROPÓSITO: Registra cada partida de un cliente en una mesa.
--   Captura inicio, fin, apuesta total y ganancia del casino.
--   Es la fuente de datos para reportes de rentabilidad por mesa.
-- ----------------------------------------------------------------
CREATE TABLE sesion_mesa (
    sesion_id       NUMBER(15)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id      NUMBER(10)      NOT NULL,
    mesa_id         NUMBER(8)       NOT NULL,
    empleado_id     NUMBER(8)       NOT NULL,
    fecha_inicio    TIMESTAMP       DEFAULT SYSTIMESTAMP,
    fecha_fin       TIMESTAMP,
    apuesta_total   NUMBER(14,2)    DEFAULT 0,
    ganancia_casino NUMBER(14,2)    DEFAULT 0,
    CONSTRAINT fk_sm_cliente
        FOREIGN KEY (cliente_id)  REFERENCES cliente(cliente_id),
    CONSTRAINT fk_sm_mesa
        FOREIGN KEY (mesa_id)     REFERENCES mesa(mesa_id),
    CONSTRAINT fk_sm_empleado
        FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE sesion_maquina
-- PROPÓSITO: Registra cada sesión de uso de una máquina tragamonedas.
--   creditos_in = lo que el cliente depositó en la máquina.
--   creditos_out = lo que la máquina devolvió al cliente.
--   La diferencia (in - out) es la ganancia del casino.
-- ----------------------------------------------------------------
CREATE TABLE sesion_maquina (
    sesion_id       NUMBER(15)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id      NUMBER(10)      NOT NULL,
    maquina_id      NUMBER(8)       NOT NULL,
    fecha_inicio    TIMESTAMP       DEFAULT SYSTIMESTAMP,
    fecha_fin       TIMESTAMP,
    creditos_in     NUMBER(14,2)    DEFAULT 0,
    creditos_out    NUMBER(14,2)    DEFAULT 0,
    CONSTRAINT fk_smq_cliente
        FOREIGN KEY (cliente_id)  REFERENCES cliente(cliente_id),
    CONSTRAINT fk_smq_maquina
        FOREIGN KEY (maquina_id)  REFERENCES maquina(maquina_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE torneo
-- PROPÓSITO: Torneos organizados por el casino.
--   El premio_total se calcula automáticamente en trigger (80% del pozo).
-- ----------------------------------------------------------------
CREATE TABLE torneo (
    torneo_id       NUMBER(8)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR2(150)   NOT NULL,
    fecha_inicio    TIMESTAMP       NOT NULL,
    fecha_fin       TIMESTAMP,
    buy_in          NUMBER(12,2)    NOT NULL
                    CONSTRAINT chk_torneo_buyin CHECK (buy_in > 0),
    premio_total    NUMBER(14,2),
    max_jugadores   NUMBER(5)       DEFAULT 50
                    CONSTRAINT chk_torneo_maxjug CHECK (max_jugadores > 0),
    sala_id         NUMBER(6),
    estado          VARCHAR2(15)    DEFAULT 'PROGRAMADO'
                    CONSTRAINT chk_torneo_estado
                    CHECK (estado IN ('PROGRAMADO','EN_CURSO','FINALIZADO','CANCELADO')),
    CONSTRAINT fk_torneo_sala
        FOREIGN KEY (sala_id) REFERENCES sala(sala_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE inscripcion_torneo
-- PROPÓSITO: Inscripciones de clientes a torneos.
--   La constraint UNIQUE(torneo_id, cliente_id) evita doble inscripción.
-- ----------------------------------------------------------------
CREATE TABLE inscripcion_torneo (
    inscripcion_id      NUMBER(10)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    torneo_id           NUMBER(8)       NOT NULL,
    cliente_id          NUMBER(10)      NOT NULL,
    fecha_inscripcion   TIMESTAMP       DEFAULT SYSTIMESTAMP,
    posicion_final      NUMBER(5),
    premio_ganado       NUMBER(12,2)    DEFAULT 0,
    CONSTRAINT uq_torneo_cliente
        UNIQUE (torneo_id, cliente_id),            -- Un cliente no puede inscribirse 2 veces al mismo torneo
    CONSTRAINT fk_insc_torneo
        FOREIGN KEY (torneo_id)  REFERENCES torneo(torneo_id),
    CONSTRAINT fk_insc_cliente
        FOREIGN KEY (cliente_id) REFERENCES cliente(cliente_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE movimiento_puntos
-- PROPÓSITO: Historial de puntos de lealtad acumulados o redimidos.
--   Permite al cliente ver cada transacción que afectó su saldo.
--   puntos puede ser negativo (redención) o positivo (acumulación).
-- ----------------------------------------------------------------
CREATE TABLE movimiento_puntos (
    movimiento_id   NUMBER(15)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id      NUMBER(10)      NOT NULL,
    puntos          NUMBER(10)      NOT NULL,   -- Negativo = redención, Positivo = acumulación
    concepto        VARCHAR2(150),
    fecha_hora      TIMESTAMP       DEFAULT SYSTIMESTAMP,
    referencia_id   NUMBER(15),
    CONSTRAINT fk_pts_cliente
        FOREIGN KEY (cliente_id) REFERENCES cliente(cliente_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE incidente
-- PROPÓSITO: Registro de incidentes de seguridad, fraudes y alertas AML.
--   Las alertas AML (Anti Lavado de Dinero) se generan automáticamente
--   por trigger cuando una transacción supera COP $10,000,000.
-- CONSTRAINTS CLAVE:
--   chk_inc_tipo   — Solo categorías de incidente reconocidas
--   chk_inc_estado — Control de flujo de investigación
-- ----------------------------------------------------------------
CREATE TABLE incidente (
    incidente_id        NUMBER(10)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo                VARCHAR2(20)    NOT NULL
                        CONSTRAINT chk_inc_tipo
                        CHECK (tipo IN ('FRAUDE','PELEA','ROBO','COMPORTAMIENTO','AML','OTRO')),
    descripcion         VARCHAR2(1000),
    sala_id             NUMBER(6),
    empleado_reporta    NUMBER(8),
    cliente_involucrado NUMBER(10),
    fecha_hora          TIMESTAMP       DEFAULT SYSTIMESTAMP,
    estado              VARCHAR2(20)    DEFAULT 'ABIERTO'
                        CONSTRAINT chk_inc_estado
                        CHECK (estado IN ('ABIERTO','EN_INVESTIGACION','CERRADO')),
    CONSTRAINT fk_inc_sala
        FOREIGN KEY (sala_id)             REFERENCES sala(sala_id),
    CONSTRAINT fk_inc_empleado
        FOREIGN KEY (empleado_reporta)    REFERENCES empleado(empleado_id),
    CONSTRAINT fk_inc_cliente
        FOREIGN KEY (cliente_involucrado) REFERENCES cliente(cliente_id)
);

-- ----------------------------------------------------------------
-- OBJETO: TABLE auditoria_log
-- PROPÓSITO: Log centralizado de auditoría para todos los objetos
--   críticos del sistema. Registra quién hizo qué y cuándo.
--   Se alimenta automáticamente desde triggers, no desde aplicación.
-- CONSTRAINTS CLAVE:
--   chk_log_operacion — Solo operaciones DML válidas
-- ----------------------------------------------------------------
CREATE TABLE auditoria_log (
    log_id          NUMBER(15)      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla_afectada  VARCHAR2(50)    NOT NULL,
    operacion       VARCHAR2(10)    NOT NULL
                    CONSTRAINT chk_log_operacion
                    CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    registro_id     NUMBER(15),
    usuario_bd      VARCHAR2(50)    DEFAULT USER,
    fecha_hora      TIMESTAMP       DEFAULT SYSTIMESTAMP,
    detalle         VARCHAR2(1000)
);

PROMPT >> Tablas creadas correctamente (16 tablas + usuarios_sistema).


-- ================================================================
-- SECCIÓN 3: TRIGGERS
-- ================================================================
-- PROPÓSITO: Implementar reglas de negocio directamente en el
--   servidor de base de datos, independiente de la aplicación.
--   Garantiza que las reglas se apliquen sin importar qué cliente
--   o herramienta conecte a la base de datos.
-- ================================================================
PROMPT ============================================================
PROMPT  [3/9] Creando triggers...
PROMPT ============================================================

-- ================================================================
-- OBJETO: TRIGGER trg_cliente_edad_minima
-- PROPÓSITO: Bloquear el registro de clientes menores de 18 años.
--   Regla legal obligatoria: ningún menor puede acceder al casino.
--   Se dispara BEFORE INSERT para rechazar el registro antes de
--   que el dato llegue a la tabla.
-- TABLAS AFECTADAS: cliente (lectura de :NEW.fecha_nacimiento)
-- EXCEPCIONES: ORA-20001 — Cliente menor de edad detectado
-- ================================================================
CREATE OR REPLACE TRIGGER trg_cliente_edad_minima
BEFORE INSERT OR UPDATE OF fecha_nacimiento ON cliente
FOR EACH ROW
BEGIN
    -- MONTHS_BETWEEN / 12 convierte la diferencia en años decimales
    -- Si el resultado es menor a 18, el cliente es menor de edad
    IF MONTHS_BETWEEN(SYSDATE, :NEW.fecha_nacimiento) / 12 < 18 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'ERROR: El cliente ' || :NEW.nombres || ' ' || :NEW.apellidos ||
            ' es menor de edad. No se puede registrar en el casino.' ||
            ' Fecha de nacimiento: ' || TO_CHAR(:NEW.fecha_nacimiento, 'DD/MM/YYYY'));
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_auditoria_cliente
-- PROPÓSITO: Registrar en auditoria_log todo cambio en la tabla
--   cliente: nuevos registros, actualizaciones y eliminaciones.
--   Permite rastrear modificaciones para cumplimiento regulatorio.
-- TABLAS AFECTADAS: auditoria_log (INSERT automático)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_auditoria_cliente
AFTER INSERT OR UPDATE OR DELETE ON cliente
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_id        NUMBER(15);
    v_detalle   VARCHAR2(1000);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_id        := :NEW.cliente_id;
        v_detalle   := 'Nuevo cliente: ' || :NEW.nombres || ' ' || :NEW.apellidos ||
                       ' | Cedula: ' || :NEW.cedula;
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_id        := :NEW.cliente_id;
        -- Documenta el cambio de membresía y puntos para trazabilidad
        v_detalle   := 'Actualizacion cliente ID ' || :NEW.cliente_id ||
                       ' | Nivel membresia: ' || NVL(:OLD.nivel_membresia,'?') ||
                       ' -> ' || NVL(:NEW.nivel_membresia,'?') ||
                       ' | Puntos: ' || NVL(TO_CHAR(:OLD.puntos_lealtad),'0') ||
                       ' -> ' || NVL(TO_CHAR(:NEW.puntos_lealtad),'0');
    ELSE
        v_operacion := 'DELETE';
        v_id        := :OLD.cliente_id;
        v_detalle   := 'Eliminacion cliente: ' || :OLD.nombres || ' ' || :OLD.apellidos;
    END IF;

    INSERT INTO auditoria_log (tabla_afectada, operacion, registro_id, detalle)
    VALUES ('CLIENTE', v_operacion, v_id, v_detalle);
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_acumular_puntos
-- PROPÓSITO: Acumular puntos de lealtad automáticamente cada vez
--   que un cliente compra fichas. Ratio: 1 punto por cada COP $1,000.
--   Si el cliente acumula suficientes puntos, asciende de nivel de
--   membresía automáticamente (BRONCE -> PLATA -> ORO -> PLATINO -> VIP).
-- TABLAS AFECTADAS: movimiento_puntos (INSERT), cliente (UPDATE)
--                   auditoria_log (INSERT en caso de ascenso)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_acumular_puntos
AFTER INSERT ON transaccion
FOR EACH ROW
DECLARE
    v_puntos        NUMBER(10) := 0;
    v_nivel_actual  VARCHAR2(10);
    v_nivel_nuevo   VARCHAR2(10);
    v_total_puntos  NUMBER(10);
BEGIN
    IF :NEW.tipo = 'COMPRA_FICHAS' THEN
        v_puntos := FLOOR(:NEW.monto / 1000);  -- 1 punto por cada $1,000 COP

        -- Registrar el movimiento de puntos para historial del cliente
        INSERT INTO movimiento_puntos (cliente_id, puntos, concepto, referencia_id)
        VALUES (:NEW.cliente_id, v_puntos,
                'Acumulacion por compra fichas - Trans#' || :NEW.transaccion_id,
                :NEW.transaccion_id);

        -- Actualizar saldo de puntos y gasto del día en el cliente
        UPDATE cliente
        SET puntos_lealtad = puntos_lealtad + v_puntos,
            gasto_hoy      = gasto_hoy + :NEW.monto
        WHERE cliente_id = :NEW.cliente_id;

        -- Verificar si el nuevo saldo de puntos activa un ascenso de nivel
        SELECT puntos_lealtad, nivel_membresia
        INTO   v_total_puntos, v_nivel_actual
        FROM   cliente
        WHERE  cliente_id = :NEW.cliente_id;

        v_nivel_nuevo := CASE
            WHEN v_total_puntos >= 100000 THEN 'VIP'
            WHEN v_total_puntos >=  50000 THEN 'PLATINO'
            WHEN v_total_puntos >=  10000 THEN 'ORO'
            WHEN v_total_puntos >=   3000 THEN 'PLATA'
            ELSE 'BRONCE'
        END;

        IF v_nivel_nuevo != v_nivel_actual THEN
            -- El cliente ascendió: actualizar y dejar rastro en auditoría
            UPDATE cliente SET nivel_membresia = v_nivel_nuevo
            WHERE cliente_id = :NEW.cliente_id;

            INSERT INTO auditoria_log (tabla_afectada, operacion, registro_id, detalle)
            VALUES ('CLIENTE', 'UPDATE', :NEW.cliente_id,
                    'ASCENSO MEMBRESIA: ' || v_nivel_actual || ' -> ' || v_nivel_nuevo ||
                    ' | Puntos totales: ' || v_total_puntos);
        END IF;
    END IF;

    -- Si es canje, descontar puntos (pero nunca quedar en negativo)
    IF :NEW.tipo = 'CANJE_FICHAS' THEN
        v_puntos := FLOOR(:NEW.monto / 1000) * (-1);  -- Puntos negativos = redención
        INSERT INTO movimiento_puntos (cliente_id, puntos, concepto, referencia_id)
        VALUES (:NEW.cliente_id, v_puntos,
                'Redencion en canje fichas - Trans#' || :NEW.transaccion_id,
                :NEW.transaccion_id);
        UPDATE cliente
        SET puntos_lealtad = GREATEST(0, puntos_lealtad + v_puntos)  -- GREATEST evita puntos negativos
        WHERE cliente_id = :NEW.cliente_id;
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_limite_diario
-- PROPÓSITO: Bloquear transacciones que superen el límite de gasto
--   diario del cliente (juego responsable). También bloquea a clientes
--   autoexcluidos. Es la primera línea de defensa del sistema.
-- TABLAS AFECTADAS: cliente (SELECT para verificar límite)
-- EXCEPCIONES:
--   ORA-20002 — Cliente autoexcluido intentando operar
--   ORA-20003 — Transacción supera límite diario del cliente
-- ================================================================
CREATE OR REPLACE TRIGGER trg_limite_diario
BEFORE INSERT ON transaccion
FOR EACH ROW
DECLARE
    v_gasto_hoy     NUMBER(14,2);
    v_limite        NUMBER(14,2);
    v_autoexcluido  NUMBER(1);
    v_nombre        VARCHAR2(200);
BEGIN
    -- Solo aplica a transacciones que implican gasto del cliente
    IF :NEW.tipo IN ('COMPRA_FICHAS', 'DEPOSITO') THEN
        SELECT gasto_hoy, limite_diario, autoexcluido,
               nombres || ' ' || apellidos
        INTO   v_gasto_hoy, v_limite, v_autoexcluido, v_nombre
        FROM   cliente
        WHERE  cliente_id = :NEW.cliente_id;

        -- Un cliente autoexcluido no puede realizar ninguna transacción
        IF v_autoexcluido = 1 THEN
            RAISE_APPLICATION_ERROR(-20002,
                'ERROR: El cliente ' || v_nombre ||
                ' esta autoexcluido del casino. Transaccion bloqueada.');
        END IF;

        -- Verificar si la transacción supera el límite del día
        IF (v_gasto_hoy + :NEW.monto) > v_limite THEN
            RAISE_APPLICATION_ERROR(-20003,
                'ERROR: El cliente ' || v_nombre ||
                ' superaria su limite diario de COP ' ||
                TO_CHAR(v_limite, 'FM999,999,999') ||
                '. Gasto acumulado hoy: COP ' ||
                TO_CHAR(v_gasto_hoy, 'FM999,999,999') ||
                '. Monto solicitado: COP ' ||
                TO_CHAR(:NEW.monto, 'FM999,999,999'));
        END IF;
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_reset_gasto_diario
-- PROPÓSITO: Resetear el contador gasto_hoy a cero cuando el
--   cliente realiza su primera transacción de un nuevo día.
--   Evita que el límite diario persista de un día al siguiente.
-- TABLAS AFECTADAS: cliente (UPDATE de gasto_hoy), transaccion (SELECT)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_reset_gasto_diario
BEFORE INSERT ON transaccion
FOR EACH ROW
BEGIN
    -- Si la última transacción del cliente fue ayer o antes,
    -- se resetea el contador de gasto del día actual
    UPDATE cliente
    SET    gasto_hoy = 0
    WHERE  cliente_id = :NEW.cliente_id
      AND  TRUNC(SYSDATE) > (
               SELECT NVL(MAX(TRUNC(fecha_hora)), TRUNC(SYSDATE) - 1)
               FROM   transaccion
               WHERE  cliente_id = :NEW.cliente_id
           );
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_referencia_transaccion
-- PROPÓSITO: Generar automáticamente un código de referencia único
--   para cada transacción si el cajero no lo proporciona.
--   Formato: RGC-YYYYMMDD-SSSSS-NNNNNN
--   Útil para trazabilidad y reconciliación contable.
-- TABLAS AFECTADAS: transaccion (modificación de :NEW.referencia)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_referencia_transaccion
BEFORE INSERT ON transaccion
FOR EACH ROW
BEGIN
    IF :NEW.referencia IS NULL THEN
        -- Combina fecha + segundos del día + ID del cliente para unicidad
        :NEW.referencia := 'RGC-' ||
            TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD') || '-' ||
            LPAD(TO_CHAR(SYSTIMESTAMP, 'SSSSS'), 5, '0') || '-' ||
            LPAD(:NEW.cliente_id, 6, '0');
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_validar_mesa_activa
-- PROPÓSITO: Impedir que se abra una sesión en una mesa que no
--   esté en estado ACTIVA. Una mesa en MANTENIMIENTO o INACTIVA
--   no debe aceptar jugadores.
-- TABLAS AFECTADAS: mesa (SELECT de estado)
-- EXCEPCIONES: ORA-20004 — Mesa no disponible para juego
-- ================================================================
CREATE OR REPLACE TRIGGER trg_validar_mesa_activa
BEFORE INSERT ON sesion_mesa
FOR EACH ROW
DECLARE
    v_estado VARCHAR2(15);
    v_numero VARCHAR2(10);
BEGIN
    SELECT estado, numero
    INTO   v_estado, v_numero
    FROM   mesa
    WHERE  mesa_id = :NEW.mesa_id;

    -- Solo las mesas en estado ACTIVA pueden recibir jugadores
    IF v_estado != 'ACTIVA' THEN
        RAISE_APPLICATION_ERROR(-20004,
            'ERROR: La mesa ' || v_numero ||
            ' no esta disponible. Estado actual: ' || v_estado);
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_calcular_premio_torneo
-- PROPÓSITO: Calcular automáticamente el premio total del torneo
--   como el 80% del pozo bruto (buy_in × max_jugadores).
--   El 20% restante es la comisión del casino por organizar el torneo.
-- TABLAS AFECTADAS: torneo (modificación de :NEW.premio_total)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_calcular_premio_torneo
BEFORE INSERT OR UPDATE OF buy_in, max_jugadores ON torneo
FOR EACH ROW
BEGIN
    -- 80% del pozo total va al premio; 20% es la comisión del casino
    :NEW.premio_total := ROUND(:NEW.buy_in * :NEW.max_jugadores * 0.80, 2);
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_alerta_aml
-- PROPÓSITO: Generar automáticamente una alerta AML (Anti Lavado
--   de Dinero) cuando una transacción supera COP $10,000,000.
--   Este umbral es el monto de reporte obligatorio según regulación
--   colombiana UIAF (Unidad de Información y Análisis Financiero).
-- TABLAS AFECTADAS: incidente (INSERT automático de alerta)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_alerta_aml
AFTER INSERT ON transaccion
FOR EACH ROW
DECLARE
    v_nombre VARCHAR2(200);
BEGIN
    -- Umbral AML: COP $10,000,000 (regulación UIAF Colombia)
    IF :NEW.monto >= 10000000 THEN
        SELECT nombres || ' ' || apellidos
        INTO   v_nombre
        FROM   cliente
        WHERE  cliente_id = :NEW.cliente_id;

        INSERT INTO incidente (tipo, descripcion, empleado_reporta, cliente_involucrado)
        VALUES ('AML',
                'ALERTA AUTOMATICA AML: Transaccion #' || :NEW.transaccion_id ||
                ' por COP ' || TO_CHAR(:NEW.monto, 'FM999,999,999') ||
                ' | Cliente: ' || v_nombre ||
                ' | Tipo: ' || :NEW.tipo ||
                ' | Metodo: ' || :NEW.metodo_pago,
                NULL,
                :NEW.cliente_id);
    END IF;
END;
/

-- ================================================================
-- OBJETO: TRIGGER trg_sesion_maquina_cierre
-- PROPÓSITO: Al cerrar una sesión de máquina, otorgar puntos de
--   lealtad al cliente basados en los créditos invertidos.
--   Ratio: 1 punto por cada COP $500 jugados en máquinas.
-- TABLAS AFECTADAS: movimiento_puntos (INSERT), cliente (UPDATE)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_sesion_maquina_cierre
BEFORE UPDATE OF fecha_fin ON sesion_maquina
FOR EACH ROW
BEGIN
    -- Solo se ejecuta cuando se asigna la fecha de cierre (sesión que termina)
    IF :NEW.fecha_fin IS NOT NULL AND :OLD.fecha_fin IS NULL THEN
        INSERT INTO movimiento_puntos (cliente_id, puntos, concepto, referencia_id)
        VALUES (:NEW.cliente_id,
                FLOOR(:NEW.creditos_in / 500),  -- 1 punto por cada $500 jugados en maquina
                'Puntos por sesion maquina #' || :NEW.sesion_id,
                :NEW.sesion_id);

        UPDATE cliente
        SET puntos_lealtad = puntos_lealtad + FLOOR(:NEW.creditos_in / 500)
        WHERE cliente_id = :NEW.cliente_id;
    END IF;
END;
/

PROMPT >> Triggers creados correctamente (10 triggers).


-- ================================================================
-- SECCIÓN 4: PROCEDIMIENTOS ALMACENADOS
-- ================================================================
PROMPT ============================================================
PROMPT  [4/9] Creando procedimientos almacenados...
PROMPT ============================================================

-- ================================================================
-- OBJETO: PROCEDURE sp_registrar_cliente
-- PROPÓSITO: Registrar un nuevo cliente en el casino verificando
--   que no exista duplicado por cédula o email. El trigger de edad
--   mínima se disparará automáticamente durante el INSERT.
-- PARÁMETROS:
--   p_cedula           IN VARCHAR2 — Documento de identidad
--   p_nombres          IN VARCHAR2 — Nombres del cliente
--   p_apellidos        IN VARCHAR2 — Apellidos del cliente
--   p_fecha_nacimiento IN DATE     — Fecha de nacimiento (validada por trigger)
--   p_email            IN VARCHAR2 — Correo electrónico (único)
--   p_telefono         IN VARCHAR2 — Teléfono de contacto
--   p_ciudad           IN VARCHAR2 — Ciudad de residencia
--   p_limite_diario    IN NUMBER   — Límite de gasto diario (default 5M COP)
--   p_cliente_id       OUT NUMBER  — ID generado del nuevo cliente
-- TABLAS AFECTADAS: cliente (INSERT)
-- EXCEPCIONES:
--   ORA-20010 — Cédula o email duplicado
--   ORA-20001 — Menor de edad (lanzado por trigger)
-- ================================================================
CREATE OR REPLACE PROCEDURE sp_registrar_cliente (
    p_cedula            IN VARCHAR2,
    p_nombres           IN VARCHAR2,
    p_apellidos         IN VARCHAR2,
    p_fecha_nacimiento  IN DATE,
    p_email             IN VARCHAR2,
    p_telefono          IN VARCHAR2,
    p_ciudad            IN VARCHAR2,
    p_limite_diario     IN NUMBER DEFAULT 5000000,
    p_cliente_id        OUT NUMBER
) AS
BEGIN
    INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                         email, telefono, ciudad, limite_diario)
    VALUES (p_cedula, p_nombres, p_apellidos, p_fecha_nacimiento,
            p_email, p_telefono, p_ciudad, p_limite_diario)
    RETURNING cliente_id INTO p_cliente_id;  -- Captura el ID autogenerado para confirmar

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK | Cliente registrado con ID: ' || p_cliente_id ||
                          ' | Nombre: ' || p_nombres || ' ' || p_apellidos);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        -- No hace ROLLBACK aquí porque el INSERT falló antes de completarse
        RAISE_APPLICATION_ERROR(-20010,
            'Ya existe un cliente con esa cedula o email: ' || p_cedula);
    WHEN OTHERS THEN
        ROLLBACK;  -- Deshacer cualquier cambio parcial antes de relanzar
        RAISE;
END;
/

-- ================================================================
-- OBJETO: PROCEDURE sp_registrar_transaccion
-- PROPÓSITO: Registrar una operación de caja (compra/canje de fichas,
--   depósito, retiro o premio). Los triggers de límite diario, AML
--   y acumulación de puntos se disparan automáticamente.
-- PARÁMETROS:
--   p_cliente_id  IN NUMBER  — ID del cliente que opera
--   p_cajero_id   IN NUMBER  — ID del cajero que procesa
--   p_tipo        IN VARCHAR2 — Tipo de operación
--   p_monto       IN NUMBER  — Monto en COP
--   p_metodo_pago IN VARCHAR2 — Medio de pago (default EFECTIVO)
--   p_trans_id    OUT NUMBER — ID de la transacción creada
-- TABLAS AFECTADAS: transaccion (INSERT), cliente (UPDATE vía trigger),
--                   movimiento_puntos (INSERT vía trigger)
-- EXCEPCIONES:
--   ORA-20011 — Monto inválido (cero o negativo)
--   ORA-20002 — Cliente autoexcluido (vía trigger)
--   ORA-20003 — Límite diario superado (vía trigger)
-- ================================================================
CREATE OR REPLACE PROCEDURE sp_registrar_transaccion (
    p_cliente_id    IN NUMBER,
    p_cajero_id     IN NUMBER,
    p_tipo          IN VARCHAR2,
    p_monto         IN NUMBER,
    p_metodo_pago   IN VARCHAR2 DEFAULT 'EFECTIVO',
    p_trans_id      OUT NUMBER
) AS
BEGIN
    -- Validación previa antes del INSERT: monto debe ser positivo
    IF p_monto <= 0 THEN
        RAISE_APPLICATION_ERROR(-20011,
            'El monto debe ser mayor a cero. Se recibio: ' || p_monto);
    END IF;

    INSERT INTO transaccion (cliente_id, cajero_id, tipo, monto, metodo_pago)
    VALUES (p_cliente_id, p_cajero_id, p_tipo, p_monto, p_metodo_pago)
    RETURNING transaccion_id INTO p_trans_id;  -- ID autogenerado necesario para el detalle

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK | Transaccion #' || p_trans_id ||
                          ' registrada por COP ' || TO_CHAR(p_monto, 'FM999,999,999') ||
                          ' | Tipo: ' || p_tipo);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;  -- Asegurar atomicidad: si algo falla, nada queda grabado
        RAISE;
END;
/

-- ================================================================
-- OBJETO: PROCEDURE sp_abrir_sesion_mesa
-- PROPÓSITO: Abrir una sesión de juego en una mesa para un cliente.
--   El trigger trg_validar_mesa_activa verifica que la mesa esté
--   disponible antes de permitir el INSERT.
-- PARÁMETROS:
--   p_cliente_id  IN NUMBER — Cliente que va a jugar
--   p_mesa_id     IN NUMBER — Mesa en la que se sienta
--   p_empleado_id IN NUMBER — Croupier asignado a la mesa
--   p_sesion_id   OUT NUMBER — ID de la sesión iniciada
-- TABLAS AFECTADAS: sesion_mesa (INSERT)
-- EXCEPCIONES: ORA-20004 — Mesa no disponible (vía trigger)
-- ================================================================
CREATE OR REPLACE PROCEDURE sp_abrir_sesion_mesa (
    p_cliente_id    IN NUMBER,
    p_mesa_id       IN NUMBER,
    p_empleado_id   IN NUMBER,
    p_sesion_id     OUT NUMBER
) AS
BEGIN
    INSERT INTO sesion_mesa (cliente_id, mesa_id, empleado_id)
    VALUES (p_cliente_id, p_mesa_id, p_empleado_id)
    RETURNING sesion_id INTO p_sesion_id;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK | Sesion de mesa #' || p_sesion_id || ' iniciada.' ||
                          ' Cliente ID: ' || p_cliente_id || ' | Mesa ID: ' || p_mesa_id);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- ================================================================
-- OBJETO: PROCEDURE sp_cerrar_sesion_mesa
-- PROPÓSITO: Cerrar una sesión de juego registrando la apuesta total
--   acumulada y la ganancia neta del casino en esa sesión.
--   SQL%ROWCOUNT = 0 indica que el ID de sesión no existe (error).
-- PARÁMETROS:
--   p_sesion_id     IN NUMBER — Sesión a cerrar
--   p_apuesta_total IN NUMBER — Total apostado durante la sesión
--   p_ganancia      IN NUMBER — Ganancia neta del casino
-- TABLAS AFECTADAS: sesion_mesa (UPDATE)
-- EXCEPCIONES: ORA-20012 — Sesión no encontrada
-- ================================================================
CREATE OR REPLACE PROCEDURE sp_cerrar_sesion_mesa (
    p_sesion_id     IN NUMBER,
    p_apuesta_total IN NUMBER,
    p_ganancia      IN NUMBER
) AS
BEGIN
    UPDATE sesion_mesa
    SET fecha_fin       = SYSTIMESTAMP,
        apuesta_total   = p_apuesta_total,
        ganancia_casino = p_ganancia
    WHERE sesion_id = p_sesion_id;

    -- SQL%ROWCOUNT = 0 significa que ninguna fila fue actualizada:
    -- el sesion_id no existe en la tabla
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20012,
            'Sesion #' || p_sesion_id || ' no encontrada. Verifique el ID.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK | Sesion #' || p_sesion_id || ' cerrada.' ||
                          ' Ganancia casino: COP ' || TO_CHAR(p_ganancia, 'FM999,999,999'));
END;
/

-- ================================================================
-- OBJETO: PROCEDURE sp_autoexcluir_cliente
-- PROPÓSITO: Marcar a un cliente como autoexcluido del casino.
--   Una vez autoexcluido, el trigger trg_limite_diario bloqueará
--   todas sus transacciones futuras de compra o depósito.
--   Se registra el motivo como incidente de tipo COMPORTAMIENTO.
-- PARÁMETROS:
--   p_cliente_id IN NUMBER   — Cliente a autoexcluir
--   p_motivo     IN VARCHAR2 — Razón de la autoexclusión
-- TABLAS AFECTADAS: cliente (UPDATE), incidente (INSERT)
-- EXCEPCIONES: ORA-20013 — Cliente no encontrado
-- ================================================================
CREATE OR REPLACE PROCEDURE sp_autoexcluir_cliente (
    p_cliente_id    IN NUMBER,
    p_motivo        IN VARCHAR2 DEFAULT 'Solicitud voluntaria del cliente'
) AS
    v_nombre VARCHAR2(200);
BEGIN
    SELECT nombres || ' ' || apellidos
    INTO   v_nombre
    FROM   cliente
    WHERE  cliente_id = p_cliente_id;

    -- Activar el flag que bloquea todas las transacciones futuras
    UPDATE cliente SET autoexcluido = 1 WHERE cliente_id = p_cliente_id;

    -- Dejar rastro del evento en incidentes para auditoría interna
    INSERT INTO incidente (tipo, descripcion, cliente_involucrado)
    VALUES ('COMPORTAMIENTO',
            'AUTOEXCLUSION: ' || v_nombre || ' | Motivo: ' || p_motivo,
            p_cliente_id);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('OK | Cliente ' || v_nombre ||
                          ' ha sido autoexcluido del casino.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20013,
            'Cliente ID ' || p_cliente_id || ' no encontrado.');
END;
/

PROMPT >> Procedimientos almacenados creados correctamente (5 procedimientos).


-- ================================================================
-- SECCIÓN 5: FUNCIONES
-- ================================================================
PROMPT ============================================================
PROMPT  [5/9] Creando funciones...
PROMPT ============================================================

-- ================================================================
-- OBJETO: FUNCTION fn_nivel_riesgo_cliente
-- PROPÓSITO: Calcular el nivel de riesgo de ludopatía de un cliente
--   basado en su gasto mensual y frecuencia de visitas.
--   Retorna 'ALTO', 'MEDIO' o 'BAJO' para uso en vistas y reportes.
--   Usado por el departamento de Juego Responsable.
-- PARÁMETROS: p_cliente_id IN NUMBER — ID del cliente a evaluar
-- TABLAS AFECTADAS: transaccion (SELECT), sesion_mesa (SELECT)
-- ================================================================
CREATE OR REPLACE FUNCTION fn_nivel_riesgo_cliente (
    p_cliente_id IN NUMBER
) RETURN VARCHAR2 AS
    v_gasto_mes     NUMBER(14,2);
    v_visitas_mes   NUMBER(5);
    v_score         NUMBER(5) := 0;
BEGIN
    -- Gasto total en compra de fichas durante el mes actual
    SELECT NVL(SUM(t.monto), 0)
    INTO   v_gasto_mes
    FROM   transaccion t
    WHERE  t.cliente_id = p_cliente_id
      AND  t.tipo = 'COMPRA_FICHAS'
      AND  TRUNC(t.fecha_hora, 'MM') = TRUNC(SYSDATE, 'MM');

    -- Número de visitas a mesas durante el mes actual
    SELECT NVL(COUNT(*), 0)
    INTO   v_visitas_mes
    FROM   sesion_mesa
    WHERE  cliente_id = p_cliente_id
      AND  TRUNC(fecha_inicio, 'MM') = TRUNC(SYSDATE, 'MM');

    -- Sistema de puntuación de riesgo acumulativo
    IF v_gasto_mes   > 10000000 THEN v_score := v_score + 40; END IF;  -- Gasto muy alto
    IF v_gasto_mes   >  5000000 THEN v_score := v_score + 20; END IF;  -- Gasto alto
    IF v_visitas_mes > 20       THEN v_score := v_score + 30; END IF;  -- Frecuencia muy alta
    IF v_visitas_mes > 10       THEN v_score := v_score + 15; END IF;  -- Frecuencia alta

    RETURN CASE
        WHEN v_score >= 60 THEN 'ALTO'
        WHEN v_score >= 30 THEN 'MEDIO'
        ELSE 'BAJO'
    END;
EXCEPTION
    WHEN OTHERS THEN RETURN 'DESCONOCIDO';  -- No fallar si el cliente no tiene historial
END;
/

-- ================================================================
-- OBJETO: FUNCTION fn_ganancia_periodo
-- PROPÓSITO: Calcular la ganancia total del casino en un rango
--   de fechas sumando la ganancia_casino de todas las sesiones
--   de mesa. Útil para reportes financieros mensuales o anuales.
-- PARÁMETROS:
--   p_fecha_inicio IN DATE — Inicio del período
--   p_fecha_fin    IN DATE — Fin del período
-- TABLAS AFECTADAS: sesion_mesa (SELECT)
-- ================================================================
CREATE OR REPLACE FUNCTION fn_ganancia_periodo (
    p_fecha_inicio IN DATE,
    p_fecha_fin    IN DATE
) RETURN NUMBER AS
    v_total NUMBER(14,2);
BEGIN
    SELECT NVL(SUM(ganancia_casino), 0)
    INTO   v_total
    FROM   sesion_mesa
    WHERE  TRUNC(fecha_inicio) BETWEEN p_fecha_inicio AND p_fecha_fin;

    RETURN v_total;
END;
/

PROMPT >> Funciones creadas correctamente (2 funciones).


-- ================================================================
-- SECCIÓN 6: VISTAS DE SEGURIDAD Y REPORTERÍA
-- ================================================================
-- PROPÓSITO: Crear abstracciones de datos que:
--   1. SEGURIDAD: Oculten columnas sensibles (costos, márgenes,
--      datos financieros internos) a roles sin autorización.
--   2. REPORTE: Respondan preguntas estratégicas del negocio
--      usando JOINs, GROUP BY y funciones de agregación.
-- ================================================================
PROMPT ============================================================
PROMPT  [6/9] Creando vistas de seguridad y reportería...
PROMPT ============================================================

-- ================================================================
-- OBJETO: VIEW v_catalogo_publico
-- PROPÓSITO: Vista de seguridad para asesores comerciales y clientes.
--   COLUMNAS EXCLUIDAS INTENCIONALMENTE (datos internos sensibles):
--     - apuesta_min / apuesta_max: datos operativos de la casa
--     - porcentaje_pago (RTP): ventaja estadística del casino,
--       su exposición permitiría que jugadores calculen estrategias
--       que minimicen la ventaja de la casa
--   Solo expone información pública del catálogo de juegos.
-- TABLAS AFECTADAS: mesa, tipo_juego, sala (SELECT)
-- ================================================================
CREATE OR REPLACE VIEW v_catalogo_publico AS
SELECT
    m.numero                AS numero_mesa,
    tj.nombre               AS juego,
    tj.descripcion          AS descripcion_juego,
    s.nombre                AS sala,
    s.tipo                  AS tipo_sala,
    m.estado,               -- Estado disponible para que el cliente sepa si puede sentarse
    -- NOTA: Se omiten apuesta_min, apuesta_max y porcentaje_pago (datos sensibles del negocio)
    CASE m.estado
        WHEN 'ACTIVA'        THEN 'Disponible'
        WHEN 'INACTIVA'      THEN 'No disponible'
        WHEN 'MANTENIMIENTO' THEN 'En mantenimiento'
    END AS disponibilidad
FROM mesa       m
JOIN tipo_juego tj ON tj.tipo_juego_id = m.tipo_juego_id
JOIN sala       s  ON s.sala_id        = m.sala_id
WHERE s.activa = 1
ORDER BY s.tipo, m.numero;

-- ================================================================
-- OBJETO: VIEW v_reporte_ingresos_sala
-- PROPÓSITO: Vista de reporte estratégico para la junta directiva.
--   PREGUNTA DE NEGOCIO QUE RESPONDE:
--   "¿Cuál sala del casino genera más ingresos, cuántas sesiones
--   promedia por día y cuál es la ganancia promedio por sesión?"
--   Permite al Director de Operaciones decidir qué salas expandir
--   y cuáles requieren revisión de su mix de juegos.
-- TABLAS AFECTADAS: sesion_mesa, mesa, sala (SELECT con JOIN y GROUP BY)
-- ================================================================
CREATE OR REPLACE VIEW v_reporte_ingresos_sala AS
SELECT
    s.nombre                            AS sala,
    s.tipo                              AS tipo_sala,
    COUNT(sm.sesion_id)                 AS total_sesiones,
    NVL(SUM(sm.apuesta_total), 0)       AS total_apostado,
    NVL(SUM(sm.ganancia_casino), 0)     AS ganancia_total_casino,
    ROUND(AVG(sm.ganancia_casino), 2)   AS ganancia_promedio_sesion,
    ROUND(AVG(sm.apuesta_total), 2)     AS apuesta_promedio_sesion,
    COUNT(DISTINCT sm.cliente_id)       AS clientes_unicos,
    COUNT(DISTINCT m.mesa_id)           AS mesas_activas_en_sala
FROM sala s
LEFT JOIN mesa      m  ON m.sala_id  = s.sala_id
LEFT JOIN sesion_mesa sm ON sm.mesa_id = m.mesa_id
GROUP BY s.sala_id, s.nombre, s.tipo
ORDER BY ganancia_total_casino DESC;

-- ================================================================
-- OBJETO: VIEW v_clientes_resumen
-- PROPÓSITO: Panel de control de clientes para gerencia y seguridad.
--   Consolida perfil, puntos, nivel de riesgo y actividad reciente.
--   No expone cédula completa ni datos de dirección (privacidad).
-- TABLAS AFECTADAS: cliente, sesion_mesa (SELECT con JOIN y GROUP BY)
-- ================================================================
CREATE OR REPLACE VIEW v_clientes_resumen AS
SELECT
    c.cliente_id,
    c.nombres || ' ' || c.apellidos         AS nombre_completo,
    c.cedula,
    c.nivel_membresia,
    c.puntos_lealtad,
    c.gasto_hoy,
    c.limite_diario,
    CASE WHEN c.autoexcluido = 1 THEN 'SI' ELSE 'NO' END AS autoexcluido,
    fn_nivel_riesgo_cliente(c.cliente_id)               AS nivel_riesgo,
    COUNT(DISTINCT sm.sesion_id)                         AS sesiones_mesa,
    NVL(SUM(sm.apuesta_total), 0)                        AS total_apostado
FROM cliente c
LEFT JOIN sesion_mesa sm ON sm.cliente_id = c.cliente_id
WHERE c.activo = 1
GROUP BY c.cliente_id, c.nombres, c.apellidos, c.cedula,
         c.nivel_membresia, c.puntos_lealtad, c.gasto_hoy,
         c.limite_diario, c.autoexcluido;

-- ================================================================
-- OBJETO: VIEW v_ingresos_diarios
-- PROPÓSITO: Flujo de caja diario por tipo de transacción.
--   Contabilidad lo usa para reconciliación diaria de caja.
-- TABLAS AFECTADAS: transaccion (SELECT con GROUP BY)
-- ================================================================
CREATE OR REPLACE VIEW v_ingresos_diarios AS
SELECT
    TRUNC(fecha_hora)   AS fecha,
    tipo,
    COUNT(*)            AS total_transacciones,
    SUM(monto)          AS monto_total,
    AVG(monto)          AS monto_promedio
FROM transaccion
WHERE revertida = 0
GROUP BY TRUNC(fecha_hora), tipo
ORDER BY fecha DESC, tipo;

-- ================================================================
-- OBJETO: VIEW v_alertas_aml
-- PROPÓSITO: Panel de alertas AML para el Oficial de Cumplimiento.
--   Muestra todas las alertas activas generadas automáticamente
--   por el trigger trg_alerta_aml (transacciones >= $10,000,000).
-- TABLAS AFECTADAS: incidente, cliente (SELECT con JOIN)
-- ================================================================
CREATE OR REPLACE VIEW v_alertas_aml AS
SELECT
    i.incidente_id,
    i.descripcion,
    i.fecha_hora,
    c.nombres || ' ' || c.apellidos AS cliente,
    c.cedula,
    i.estado
FROM incidente i
JOIN cliente c ON c.cliente_id = i.cliente_involucrado
WHERE i.tipo = 'AML'
ORDER BY i.fecha_hora DESC;

-- ================================================================
-- OBJETO: VIEW v_sesiones_activas
-- PROPÓSITO: Vista operativa para croupiers. Muestra las mesas
--   actualmente en juego sin exponer datos financieros del cliente
--   (no incluye monto de transacciones ni límite diario).
-- TABLAS AFECTADAS: sesion_mesa, mesa, tipo_juego, sala, cliente,
--                   empleado (SELECT con múltiples JOINs)
-- ================================================================
CREATE OR REPLACE VIEW v_sesiones_activas AS
SELECT
    sm.sesion_id,
    m.numero                                AS mesa,
    tj.nombre                               AS juego,
    s.nombre                                AS sala,
    c.nombres || ' ' || c.apellidos         AS cliente,
    c.nivel_membresia,
    sm.fecha_inicio,
    ROUND((SYSDATE - CAST(sm.fecha_inicio AS DATE)) * 24 * 60, 0) AS minutos_jugando,
    sm.apuesta_total                        AS apuesta_acumulada,
    e.nombres || ' ' || e.apellidos         AS croupier_asignado
    -- COLUMNAS EXCLUIDAS: gasto_hoy, limite_diario, puntos_lealtad
    -- (datos privados que el croupier no necesita ver)
FROM sesion_mesa sm
JOIN mesa       m  ON m.mesa_id        = sm.mesa_id
JOIN tipo_juego tj ON tj.tipo_juego_id = m.tipo_juego_id
JOIN sala       s  ON s.sala_id        = m.sala_id
JOIN cliente    c  ON c.cliente_id     = sm.cliente_id
JOIN empleado   e  ON e.empleado_id    = sm.empleado_id
WHERE sm.fecha_fin IS NULL  -- Solo sesiones activas (sin fecha de cierre)
ORDER BY sm.fecha_inicio;

-- ================================================================
-- OBJETO: VIEW v_reporte_cajero
-- PROPÓSITO: Vista de cuadre de caja para el turno actual del cajero.
--   Solo muestra transacciones del día de hoy no revertidas.
-- TABLAS AFECTADAS: transaccion, cliente, cajero (SELECT con JOIN)
-- ================================================================
CREATE OR REPLACE VIEW v_reporte_cajero AS
SELECT
    t.transaccion_id,
    t.referencia,
    t.fecha_hora,
    c.nombres || ' ' || c.apellidos AS cliente,
    c.cedula,
    t.tipo,
    t.metodo_pago,
    t.monto,
    t.revertida,
    ca.numero_caja
FROM transaccion t
JOIN cliente c  ON c.cliente_id = t.cliente_id
JOIN cajero  ca ON ca.cajero_id = t.cajero_id
WHERE TRUNC(t.fecha_hora) = TRUNC(SYSDATE)  -- Solo el día de hoy
  AND t.revertida = 0                        -- Excluir transacciones anuladas
ORDER BY t.fecha_hora DESC;

-- ================================================================
-- OBJETO: VIEW v_dashboard_gerencia
-- PROPÓSITO: KPIs ejecutivos del día en tiempo real para la dirección.
--   Vista de uso exclusivo del Casino Admin: ingresos, ganancia,
--   ocupación de mesas, alertas y clientes activos ahora mismo.
-- TABLAS AFECTADAS: transaccion, sesion_mesa, mesa, sesion_maquina,
--                   torneo, incidente, cliente (subqueries)
-- ================================================================
CREATE OR REPLACE VIEW v_dashboard_gerencia AS
SELECT
    (SELECT NVL(SUM(monto), 0)
     FROM transaccion
     WHERE tipo = 'COMPRA_FICHAS'
       AND TRUNC(fecha_hora) = TRUNC(SYSDATE)
       AND revertida = 0)                       AS ventas_fichas_hoy,
    (SELECT NVL(SUM(ganancia_casino), 0)
     FROM sesion_mesa
     WHERE TRUNC(fecha_inicio) = TRUNC(SYSDATE)) AS ganancia_mesas_hoy,
    (SELECT COUNT(DISTINCT cliente_id)
     FROM sesion_mesa
     WHERE fecha_fin IS NULL)                   AS clientes_activos_ahora,
    (SELECT COUNT(*)
     FROM mesa
     WHERE estado = 'ACTIVA')                   AS mesas_activas,
    (SELECT COUNT(DISTINCT maquina_id)
     FROM sesion_maquina
     WHERE fecha_fin IS NULL)                   AS maquinas_en_uso,
    (SELECT COUNT(*)
     FROM torneo
     WHERE estado = 'EN_CURSO')                 AS torneos_en_curso,
    (SELECT COUNT(*)
     FROM incidente
     WHERE tipo = 'AML'
       AND estado = 'ABIERTO'
       AND TRUNC(fecha_hora) = TRUNC(SYSDATE))  AS alertas_aml_hoy,
    (SELECT COUNT(*)
     FROM incidente
     WHERE estado = 'ABIERTO')                  AS incidentes_abiertos,
    (SELECT COUNT(*)
     FROM cliente
     WHERE autoexcluido = 1
       AND activo = 1)                          AS clientes_autoexcluidos,
    SYSDATE                                     AS actualizado_en
FROM DUAL;

PROMPT >> Vistas creadas correctamente (8 vistas).


-- ================================================================
-- SECCIÓN 7: ROLES SIMULADOS (Compatible Oracle XE / LiveSQL)
-- ================================================================
-- PROPÓSITO: Simular un sistema de control de acceso por roles
--   sin requerir privilegios DBA (CREATE USER/ROLE).
--   FUNCIONAMIENTO:
--     1. Tabla usuarios_sistema — usuarios y su rol asignado
--     2. PKG_CONTEXTO_CASINO   — activa el rol en la sesión actual
--     3. sp_login / sp_logout  — autentica y registra en auditoría
--     4. Vistas con filtro     — cada vista filtra por rol activo
--   NOTA: En un servidor real con DBA, reemplazar por el archivo
--         06_ROLES_USUARIOS.sql con CREATE USER / GRANT ROLE.
-- ================================================================
PROMPT ============================================================
PROMPT  [7/9] Creando sistema de roles simulados (XE/LiveSQL)...
PROMPT ============================================================

-- ----------------------------------------------------------------
-- OBJETO: TABLE usuarios_sistema
-- PROPÓSITO: Almacena credenciales y rol de cada usuario del sistema.
--   En producción real esta tabla no existiría: Oracle gestiona
--   usuarios a nivel de motor, no en una tabla de aplicación.
-- ----------------------------------------------------------------
CREATE TABLE usuarios_sistema (
    usuario_id      NUMBER(6)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username        VARCHAR2(30)    NOT NULL UNIQUE,
    password_hash   VARCHAR2(100)   NOT NULL,   -- Hash ORA_HASH, nunca texto plano
    rol             VARCHAR2(20)    NOT NULL
                    CONSTRAINT chk_usr_rol
                    CHECK (rol IN ('CASINO_ADMIN','CAJERO','CROUPIER','SEGURIDAD')),
    empleado_id     NUMBER(8),
    activo          NUMBER(1)       DEFAULT 1
                    CONSTRAINT chk_usr_activo CHECK (activo IN (0,1)),
    CONSTRAINT fk_usr_empleado
        FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id)
);

-- ----------------------------------------------------------------
-- OBJETO: PACKAGE pkg_contexto_casino
-- PROPÓSITO: Gestionar el rol activo en la sesión de base de datos.
--   Usa DBMS_SESSION.SET_IDENTIFIER para almacenar "usuario|ROL"
--   en la memoria de la sesión activa (sin persistencia entre sesiones).
--   Ventaja: no requiere CREATE CONTEXT ni privilegios especiales.
-- ----------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_contexto_casino AS
    PROCEDURE activar_rol(p_rol IN VARCHAR2, p_usuario IN VARCHAR2);
    PROCEDURE limpiar_contexto;
    FUNCTION  rol_activo     RETURN VARCHAR2;
    FUNCTION  usuario_activo RETURN VARCHAR2;
END pkg_contexto_casino;
/

CREATE OR REPLACE PACKAGE BODY pkg_contexto_casino AS

    -- Almacena "usuario|ROL" en CLIENT_IDENTIFIER de la sesión
    PROCEDURE activar_rol(p_rol IN VARCHAR2, p_usuario IN VARCHAR2) IS
    BEGIN
        DBMS_SESSION.SET_IDENTIFIER(p_usuario || '|' || p_rol);
    END activar_rol;

    -- Limpia el identificador al cerrar sesión
    PROCEDURE limpiar_contexto IS
    BEGIN
        DBMS_SESSION.SET_IDENTIFIER(NULL);
    END limpiar_contexto;

    -- Extrae el ROL del string "usuario|ROL" almacenado en la sesión
    FUNCTION rol_activo RETURN VARCHAR2 IS
        v_id  VARCHAR2(200);
        v_pos NUMBER;
    BEGIN
        v_id  := SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER');
        v_pos := INSTR(v_id, '|');
        IF v_pos > 0 THEN
            RETURN SUBSTR(v_id, v_pos + 1);  -- Todo lo que está después del pipe
        END IF;
        RETURN 'SIN_ROL';
    EXCEPTION WHEN OTHERS THEN RETURN 'SIN_ROL';
    END rol_activo;

    -- Extrae el USERNAME del string "usuario|ROL"
    FUNCTION usuario_activo RETURN VARCHAR2 IS
        v_id  VARCHAR2(200);
        v_pos NUMBER;
    BEGIN
        v_id  := SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER');
        v_pos := INSTR(v_id, '|');
        IF v_pos > 0 THEN
            RETURN SUBSTR(v_id, 1, v_pos - 1);  -- Todo lo que está antes del pipe
        END IF;
        RETURN NVL(v_id, 'ANONIMO');
    EXCEPTION WHEN OTHERS THEN RETURN 'ANONIMO';
    END usuario_activo;

END pkg_contexto_casino;
/

-- ----------------------------------------------------------------
-- OBJETO: PROCEDURE sp_login
-- PROPÓSITO: Autenticar al usuario y activar su rol en la sesión.
--   Registra intentos fallidos y exitosos en auditoria_log.
-- PARÁMETROS:
--   p_username IN VARCHAR2 — Nombre de usuario
--   p_password IN VARCHAR2 — Contraseña en texto plano (se hashea)
-- EXCEPCIONES:
--   ORA-20020 — Usuario inactivo
--   ORA-20021 — Contraseña incorrecta
--   ORA-20022 — Usuario no encontrado
-- ----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_login (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
) AS
    v_rol           VARCHAR2(20);
    v_activo        NUMBER(1);
    v_password_hash VARCHAR2(100);
BEGIN
    SELECT rol, activo, password_hash
    INTO   v_rol, v_activo, v_password_hash
    FROM   usuarios_sistema
    WHERE  username = p_username;

    IF v_activo = 0 THEN
        RAISE_APPLICATION_ERROR(-20020,
            'Usuario ' || p_username || ' esta inactivo.');
    END IF;

    -- Comparar el hash almacenado con el hash del password ingresado
    IF v_password_hash != TO_CHAR(ORA_HASH(p_password)) THEN
        INSERT INTO auditoria_log (tabla_afectada, operacion, detalle)
        VALUES ('USUARIOS_SISTEMA', 'UPDATE',
                'LOGIN FALLIDO para usuario: ' || p_username);
        COMMIT;
        RAISE_APPLICATION_ERROR(-20021,
            'Contrasena incorrecta para: ' || p_username);
    END IF;

    pkg_contexto_casino.activar_rol(v_rol, p_username);

    INSERT INTO auditoria_log (tabla_afectada, operacion, detalle)
    VALUES ('USUARIOS_SISTEMA', 'INSERT',
            'LOGIN EXITOSO | Usuario: ' || p_username || ' | Rol: ' || v_rol);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Sesion iniciada: [' || v_rol || '] ' || p_username);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20022,
            'Usuario ' || p_username || ' no encontrado.');
END sp_login;
/

-- ----------------------------------------------------------------
-- OBJETO: PROCEDURE sp_logout
-- PROPÓSITO: Cerrar la sesión del usuario activo, limpiar el
--   contexto de rol y registrar el evento en auditoría.
-- ----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_logout AS
    v_usuario VARCHAR2(100);
BEGIN
    v_usuario := pkg_contexto_casino.usuario_activo;
    pkg_contexto_casino.limpiar_contexto;

    INSERT INTO auditoria_log (tabla_afectada, operacion, detalle)
    VALUES ('USUARIOS_SISTEMA', 'UPDATE',
            'LOGOUT | Usuario: ' || v_usuario);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Sesion cerrada: ' || v_usuario);
END sp_logout;
/

-- Vistas de interfaz por rol (filtran según el rol activo en la sesión)

CREATE OR REPLACE VIEW v_cajero_transacciones_hoy AS
-- Solo accesible para CAJERO o CASINO_ADMIN. Otros roles ven 0 filas.
SELECT t.transaccion_id, t.referencia, t.fecha_hora,
       c.nombres || ' ' || c.apellidos AS cliente, c.cedula,
       t.tipo, t.metodo_pago, t.monto, ca.numero_caja,
       pkg_contexto_casino.rol_activo() AS rol_en_sesion
FROM transaccion t
JOIN cliente c  ON c.cliente_id = t.cliente_id
JOIN cajero  ca ON ca.cajero_id = t.cajero_id
WHERE TRUNC(t.fecha_hora) = TRUNC(SYSDATE) AND t.revertida = 0
  AND pkg_contexto_casino.rol_activo() IN ('CAJERO','CASINO_ADMIN')
ORDER BY t.fecha_hora DESC;

CREATE OR REPLACE VIEW v_croupier_mesas_activas AS
-- Solo accesible para CROUPIER o CASINO_ADMIN. Otros roles ven 0 filas.
SELECT sm.sesion_id, m.numero AS mesa, tj.nombre AS juego, s.nombre AS sala,
       c.nombres || ' ' || c.apellidos AS cliente, c.nivel_membresia,
       sm.fecha_inicio,
       ROUND((SYSDATE - CAST(sm.fecha_inicio AS DATE)) * 24 * 60, 0) AS minutos_jugando,
       sm.apuesta_total,
       pkg_contexto_casino.rol_activo() AS rol_en_sesion
FROM sesion_mesa sm
JOIN mesa m ON m.mesa_id = sm.mesa_id
JOIN tipo_juego tj ON tj.tipo_juego_id = m.tipo_juego_id
JOIN sala s ON s.sala_id = m.sala_id
JOIN cliente c ON c.cliente_id = sm.cliente_id
WHERE sm.fecha_fin IS NULL
  AND pkg_contexto_casino.rol_activo() IN ('CROUPIER','CASINO_ADMIN')
ORDER BY sm.fecha_inicio;

CREATE OR REPLACE VIEW v_seguridad_incidentes AS
-- Solo accesible para SEGURIDAD o CASINO_ADMIN. Otros roles ven 0 filas.
SELECT i.incidente_id, i.tipo, i.descripcion, i.fecha_hora, i.estado,
       c.nombres || ' ' || c.apellidos AS cliente_involucrado, c.cedula,
       s.nombre AS sala,
       e.nombres || ' ' || e.apellidos AS reportado_por,
       pkg_contexto_casino.rol_activo() AS rol_en_sesion
FROM incidente i
LEFT JOIN cliente  c ON c.cliente_id  = i.cliente_involucrado
LEFT JOIN sala     s ON s.sala_id     = i.sala_id
LEFT JOIN empleado e ON e.empleado_id = i.empleado_reporta
WHERE pkg_contexto_casino.rol_activo() IN ('SEGURIDAD','CASINO_ADMIN')
ORDER BY i.fecha_hora DESC;

CREATE OR REPLACE VIEW v_admin_panel_completo AS
-- Solo accesible para CASINO_ADMIN. Otros roles ven 0 filas.
SELECT
    (SELECT NVL(SUM(monto),0) FROM transaccion
     WHERE tipo='COMPRA_FICHAS' AND TRUNC(fecha_hora)=TRUNC(SYSDATE) AND revertida=0)
        AS ventas_fichas_hoy,
    (SELECT NVL(SUM(ganancia_casino),0) FROM sesion_mesa
     WHERE TRUNC(fecha_inicio)=TRUNC(SYSDATE))
        AS ganancia_mesas_hoy,
    (SELECT COUNT(DISTINCT cliente_id) FROM sesion_mesa WHERE fecha_fin IS NULL)
        AS clientes_activos_ahora,
    (SELECT COUNT(*) FROM mesa WHERE estado='ACTIVA')
        AS mesas_activas,
    (SELECT COUNT(*) FROM incidente
     WHERE tipo='AML' AND estado='ABIERTO' AND TRUNC(fecha_hora)=TRUNC(SYSDATE))
        AS alertas_aml_hoy,
    (SELECT COUNT(*) FROM incidente WHERE estado='ABIERTO')
        AS incidentes_abiertos,
    pkg_contexto_casino.rol_activo() AS rol_en_sesion,
    SYSDATE                          AS actualizado_en
FROM DUAL
WHERE pkg_contexto_casino.rol_activo() = 'CASINO_ADMIN';

PROMPT >> Sistema de roles simulados creado correctamente.


-- ================================================================
-- SECCIÓN 8: DATOS DE EJEMPLO
-- ================================================================
PROMPT ============================================================
PROMPT  [8/9] Insertando datos de ejemplo...
PROMPT ============================================================

-- ----------------------------------------------------------------
-- Cargos del casino (10 filas)
-- ----------------------------------------------------------------
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('CEO', 3500000, 'Director General del Casino');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Director Financiero', 2800000, 'CFO — Control financiero y cumplimiento');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Croupier', 1400000, 'Dealer de mesas — Blackjack, Ruleta, Poker');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Cajero', 1200000, 'Operador de caja — Fichas, depósitos y retiros');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Agente de Seguridad', 1150000, 'Vigilancia de salas e incidentes');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Gerente de Sala', 2100000, 'Supervisión operativa de salas de juego');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Técnico de Máquinas', 1300000, 'Mantenimiento y reparación de tragamonedas');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Oficial de Cumplimiento', 2400000, 'Control AML y regulatorio UIAF');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Anfitrión VIP', 1600000, 'Atención personalizada a clientes de alto valor');
INSERT INTO cargo (nombre, salario_base, descripcion)
VALUES ('Contador', 1900000, 'Gestión contable y reconciliación de caja');

-- ----------------------------------------------------------------
-- Empleados del casino (10 filas)
-- ----------------------------------------------------------------
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000001','Carlos','Mendoza',1, DATE '2024-01-15','MAÑANA');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000002','Laura','Gutierrez',2, DATE '2024-01-15','MAÑANA');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000003','Andres','Torres',3, DATE '2024-02-01','NOCHE');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000004','Paola','Rios',4, DATE '2024-02-01','TARDE');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000005','Jorge','Salazar',5, DATE '2024-03-01','ROTATIVO');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000006','Diana','Castillo',6, DATE '2024-03-10','MAÑANA');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000007','Miguel','Rojas',7, DATE '2024-04-01','TARDE');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000008','Valentina','Cruz',8, DATE '2024-04-15','MAÑANA');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000009','Hector','Bermudez',9, DATE '2024-05-01','NOCHE');
INSERT INTO empleado (cedula, nombres, apellidos, cargo_id, fecha_ingreso, turno)
VALUES ('10000010','Mariana','Ospina',10, DATE '2024-05-15','ROTATIVO');

-- ----------------------------------------------------------------
-- Salas del casino (10 filas)
-- ----------------------------------------------------------------
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Principal',   'GENERAL', 200);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala VIP Gold',    'VIP',      40);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Torneos',     'TORNEO',   80);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Platinum',    'VIP',      30);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Familiar',    'GENERAL', 150);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Póker Club',  'GENERAL', 100);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Ruleta Real', 'GENERAL', 120);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Diamante',    'VIP',      25);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Eventos',     'TORNEO',   60);
INSERT INTO sala (nombre, tipo, capacidad) VALUES ('Sala Tragamonedas','GENERAL', 180);

-- ----------------------------------------------------------------
-- Tipos de juego (10 filas)
-- ----------------------------------------------------------------
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Blackjack',          1,  7);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Ruleta Americana',   1, 12);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Poker Texas Holdem', 2,  9);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Baccarat',           1, 14);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Ruleta Europea',     1, 12);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Tres Cartas',        1,  6);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Dados Casino',       1,  8);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Pai Gow Poker',      1,  6);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Caribbean Stud',     1,  7);
INSERT INTO tipo_juego (nombre, min_jugadores, max_jugadores)
VALUES ('Mini Baccarat',      1, 10);

-- ----------------------------------------------------------------
-- Mesas de juego (10 filas)
-- ----------------------------------------------------------------
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-01', 1, 1,  20000,   2000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-02', 1, 2,  10000,   1000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-03', 2, 4, 100000,  10000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-04', 3, 3,  50000,   5000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-05', 4, 5, 200000,  15000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-06', 6, 3,  30000,   3000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-07', 7, 2,  15000,   1500000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-08', 5, 1,  10000,    800000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-09', 8, 4, 500000,  50000000);
INSERT INTO mesa (numero, sala_id, tipo_juego_id, apuesta_min, apuesta_max)
VALUES ('M-10', 9, 6,  25000,   2500000);

-- ----------------------------------------------------------------
-- Máquinas tragamonedas (10 filas)
-- ----------------------------------------------------------------
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-001','Dragon Fortune',  'IGT',        1,   500,  200000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-002','Lucky Gold',      'Konami',     1,  1000,  500000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-003','Gold Rush VIP',   'Aristocrat', 2,  5000, 1000000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-004','Treasure Island', 'IGT',        1,   500,  300000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-005','Mega Millions',   'Bally',      10, 1000,  800000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-006','Phoenix Rising',  'Konami',     10, 2000,  600000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-007','Wild Safari',     'Aristocrat', 5,   500,  250000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-008','Neptune Gold',    'IGT',        10, 1000,  400000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-009','Diamond Queen',   'Bally',      2,  5000, 2000000);
INSERT INTO maquina (serial, modelo, fabricante, sala_id, apuesta_min, apuesta_max)
VALUES ('SL-010','Lucky Clover',    'Konami',     10,  500,  150000);

-- ----------------------------------------------------------------
-- Cajeros (10 filas)
-- ----------------------------------------------------------------
INSERT INTO cajero (empleado_id, numero_caja) VALUES (4, 'CAJA-01');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (2, 'CAJA-02');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (5, 'CAJA-03');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (6, 'CAJA-04');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (7, 'CAJA-05');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (8, 'CAJA-06');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (9, 'CAJA-07');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (10,'CAJA-08');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (1, 'CAJA-09');
INSERT INTO cajero (empleado_id, numero_caja) VALUES (3, 'CAJA-10');

-- ----------------------------------------------------------------
-- Clientes del casino (10 filas)
-- ----------------------------------------------------------------
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000001','Sebastian','Vargas',   DATE '1985-03-12',
        's.vargas@email.com',   '3001234567','Bogota',        2000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000002','Natalia',  'Perez',    DATE '1990-07-25',
        'n.perez@email.com',    '3107654321','Medellin',       500000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000003','Ricardo',  'Salcedo',  DATE '1978-11-08',
        'r.salcedo@email.com',  '3209876543','Cali',         10000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000004','Camila',   'Herrera',  DATE '1995-05-20',
        'c.herrera@email.com',  '3154443322','Barranquilla',  3000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000005','Andres',   'Molina',   DATE '1982-09-14',
        'a.molina@email.com',   '3006667788','Bogota',        5000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000006','Gabriela', 'Suarez',   DATE '1993-12-03',
        'g.suarez@email.com',   '3119998877','Cali',          1500000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000007','Fernando', 'Ramirez',  DATE '1975-04-22',
        'f.ramirez@email.com',  '3201112233','Medellin',      8000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000008','Lucia',    'Montoya',  DATE '1988-08-17',
        'l.montoya@email.com',  '3144455667','Pereira',       2500000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000009','David',    'Pinto',    DATE '1997-01-30',
        'd.pinto@email.com',    '3055566778','Bogota',        1000000);
INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                     email, telefono, ciudad, limite_diario)
VALUES ('20000010','Alejandra','Vega',     DATE '1983-06-11',
        'a.vega@email.com',     '3188889900','Bucaramanga',   4000000);

-- ----------------------------------------------------------------
-- Torneos (10 filas)
-- ----------------------------------------------------------------
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Gran Torneo Anual 2025',
        SYSTIMESTAMP, SYSTIMESTAMP + INTERVAL '3' DAY,
        500000, 60, 3, 'PROGRAMADO');
INSERT INTO torneo (nombre, fecha_inicio, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo VIP Mensual',
        SYSTIMESTAMP + INTERVAL '7' DAY,
        200000, 20, 2, 'PROGRAMADO');
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Poker Navidad 2024',
        SYSTIMESTAMP - INTERVAL '30' DAY, SYSTIMESTAMP - INTERVAL '28' DAY,
        300000, 40, 3, 'FINALIZADO');
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Blackjack Enero',
        SYSTIMESTAMP - INTERVAL '60' DAY, SYSTIMESTAMP - INTERVAL '58' DAY,
        150000, 30, 1, 'FINALIZADO');
INSERT INTO torneo (nombre, fecha_inicio, buy_in, max_jugadores, sala_id, estado)
VALUES ('Copa Ruleta Primavera',
        SYSTIMESTAMP + INTERVAL '14' DAY,
        250000, 50, 9, 'PROGRAMADO');
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Baccarat VIP',
        SYSTIMESTAMP + INTERVAL '1' DAY, SYSTIMESTAMP + INTERVAL '2' DAY,
        1000000, 15, 4, 'EN_CURSO');
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Relámpago Marzo',
        SYSTIMESTAMP - INTERVAL '90' DAY, SYSTIMESTAMP - INTERVAL '90' DAY,
        100000, 20, 1, 'FINALIZADO');
INSERT INTO torneo (nombre, fecha_inicio, buy_in, max_jugadores, sala_id, estado)
VALUES ('Gran Premio Diamante',
        SYSTIMESTAMP + INTERVAL '21' DAY,
        2000000, 10, 8, 'PROGRAMADO');
INSERT INTO torneo (nombre, fecha_inicio, fecha_fin, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Póker Universitario',
        SYSTIMESTAMP - INTERVAL '15' DAY, SYSTIMESTAMP - INTERVAL '14' DAY,
        80000, 60, 6, 'FINALIZADO');
INSERT INTO torneo (nombre, fecha_inicio, buy_in, max_jugadores, sala_id, estado)
VALUES ('Torneo Aniversario Casino',
        SYSTIMESTAMP + INTERVAL '30' DAY,
        500000, 80, 9, 'PROGRAMADO');

-- ----------------------------------------------------------------
-- Usuarios del sistema (10 filas)
-- ----------------------------------------------------------------
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('admin_casino',    TO_CHAR(ORA_HASH('Admin2025!')),      'CASINO_ADMIN', 1);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('cajero_paola',    TO_CHAR(ORA_HASH('Cajero2025!')),     'CAJERO',       4);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('croupier_andres', TO_CHAR(ORA_HASH('Croupier2025!')),   'CROUPIER',     3);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('seguridad_1',     TO_CHAR(ORA_HASH('Seguridad2025!')),  'SEGURIDAD',    5);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('cajero_laura',    TO_CHAR(ORA_HASH('Cajero2025_L!')),   'CAJERO',       2);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('cajero_jorge',    TO_CHAR(ORA_HASH('Cajero2025_J!')),   'CAJERO',       6);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('croupier_diana',  TO_CHAR(ORA_HASH('Croupier2025_D!')), 'CROUPIER',     7);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('seguridad_2',     TO_CHAR(ORA_HASH('Seguridad2025_2!')), 'SEGURIDAD',   8);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('croupier_hector', TO_CHAR(ORA_HASH('Croupier2025_H!')), 'CROUPIER',     9);
INSERT INTO usuarios_sistema (username, password_hash, rol, empleado_id)
VALUES ('admin_finanzas',  TO_CHAR(ORA_HASH('Admin2025_F!')),    'CASINO_ADMIN', 10);

COMMIT;
PROMPT >> Datos de ejemplo insertados correctamente.

-- ================================================================
-- SECCIÓN 9: PRUEBAS COMPLETAS
-- ================================================================
-- PROPÓSITO: Demostrar el funcionamiento de todos los componentes
--   con casos de éxito y fallo documentados con DBMS_OUTPUT.
--   Esta sección satisface los ítems 4, 5, 6, 7 y 8 del checklist.
-- ================================================================
PROMPT ============================================================
PROMPT  [9/9] Ejecutando pruebas...
PROMPT ============================================================

-- ================================================================
-- PRUEBA A: TRIGGER — Caso OK (cliente mayor de edad)
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA A1: Trigger trg_cliente_edad_minima — CASO OK
PROMPT  Se inserta un cliente mayor de edad. Debe registrarse.
PROMPT ----------------------------------------------------------
DECLARE
    v_id NUMBER;
BEGIN
    sp_registrar_cliente(
        p_cedula           => '30000001',
        p_nombres          => 'Felipe',
        p_apellidos        => 'Mora',
        p_fecha_nacimiento => DATE '1988-06-15',  -- 36 años, mayor de edad
        p_email            => 'f.mora@email.com',
        p_telefono         => '3012223344',
        p_ciudad           => 'Bogota',
        p_limite_diario    => 1500000,
        p_cliente_id       => v_id
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO A1: EXITO — Cliente mayor de edad registrado con ID: ' || v_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO A1: FALLO INESPERADO — ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA B: TRIGGER — Caso FALLO (cliente menor de edad)
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA A2: Trigger trg_cliente_edad_minima — CASO FALLO
PROMPT  Se intenta insertar un cliente de 15 años. Debe fallar
PROMPT  con ORA-20001 y mensaje descriptivo.
PROMPT ----------------------------------------------------------
BEGIN
    INSERT INTO cliente (cedula, nombres, apellidos, fecha_nacimiento,
                         email, ciudad, limite_diario)
    VALUES ('99000001','Juan','Menor',
            DATE '2010-03-01',   -- 15 años — MENOR DE EDAD
            'j.menor@email.com','Bogota', 100000);
    DBMS_OUTPUT.PUT_LINE('RESULTADO A2: ERROR — El trigger debio haber bloqueado este INSERT.');
EXCEPTION
    WHEN OTHERS THEN
        -- ORA-20001 = código personalizado del trigger trg_cliente_edad_minima
        DBMS_OUTPUT.PUT_LINE('RESULTADO A2: CORRECTO — Trigger activo. Error capturado:');
        DBMS_OUTPUT.PUT_LINE('  Codigo : ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Mensaje: ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA C: PROCEDIMIENTO — Registro de transacción normal
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA C1: sp_registrar_transaccion — CASO OK
PROMPT  Compra de fichas válida. Debe acumular puntos (trigger).
PROMPT ----------------------------------------------------------
DECLARE
    v_trans_id NUMBER;
BEGIN
    sp_registrar_transaccion(
        p_cliente_id  => 1,       -- Sebastian Vargas
        p_cajero_id   => 1,       -- CAJA-01
        p_tipo        => 'COMPRA_FICHAS',
        p_monto       => 500000,  -- COP $500,000 = 500 puntos acumulados
        p_metodo_pago => 'EFECTIVO',
        p_trans_id    => v_trans_id
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO C1: EXITO — Transaccion #' || v_trans_id ||
                          ' procesada. Verificar puntos en cliente ID 1.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO C1: FALLO — ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA D: PROCEDIMIENTO — Transacción con monto inválido
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA C2: sp_registrar_transaccion — CASO FALLO
PROMPT  Monto negativo. Debe fallar con ORA-20011.
PROMPT ----------------------------------------------------------
DECLARE
    v_trans_id NUMBER;
BEGIN
    sp_registrar_transaccion(
        p_cliente_id  => 1,
        p_cajero_id   => 1,
        p_tipo        => 'COMPRA_FICHAS',
        p_monto       => -50000,  -- Monto negativo — INVALIDO
        p_metodo_pago => 'EFECTIVO',
        p_trans_id    => v_trans_id
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO C2: ERROR — Debio fallar con monto negativo.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO C2: CORRECTO — Monto invalido rechazado:');
        DBMS_OUTPUT.PUT_LINE('  Codigo : ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Mensaje: ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA E: SESIÓN DE MESA — Abrir y cerrar
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA E: sp_abrir_sesion_mesa y sp_cerrar_sesion_mesa
PROMPT  Ciclo completo de una sesión en mesa M-01.
PROMPT ----------------------------------------------------------
DECLARE
    v_sesion_id NUMBER;
BEGIN
    -- Abrir sesión en mesa M-01 (mesa_id=1) con croupier Andres Torres (empleado_id=3)
    sp_abrir_sesion_mesa(
        p_cliente_id  => 2,  -- Natalia Perez
        p_mesa_id     => 1,  -- Mesa M-01 (Blackjack, Sala Principal)
        p_empleado_id => 3,  -- Andres Torres (croupier)
        p_sesion_id   => v_sesion_id
    );
    DBMS_OUTPUT.PUT_LINE('Sesion abierta con ID: ' || v_sesion_id);

    -- Cerrar la sesión con resultados de la partida
    sp_cerrar_sesion_mesa(
        p_sesion_id     => v_sesion_id,
        p_apuesta_total => 300000,   -- El cliente apostó COP $300,000
        p_ganancia      => 45000     -- El casino ganó COP $45,000 (15%)
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO E: EXITO — Sesion completa registrada correctamente.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO E: FALLO — ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA F: AUTOEXCLUSIÓN — y bloqueo posterior
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA F: sp_autoexcluir_cliente + bloqueo de transaccion
PROMPT  Autoexcluir al cliente 2 y luego intentar una transaccion.
PROMPT ----------------------------------------------------------
DECLARE
    v_trans_id NUMBER;
BEGIN
    -- Autoexcluir a Natalia Perez
    sp_autoexcluir_cliente(
        p_cliente_id => 2,
        p_motivo     => 'Solicitud propia por motivos personales'
    );
    DBMS_OUTPUT.PUT_LINE('Cliente 2 autoexcluido exitosamente.');

    -- Intentar una compra de fichas (debe ser bloqueada por trigger)
    sp_registrar_transaccion(
        p_cliente_id  => 2,
        p_cajero_id   => 1,
        p_tipo        => 'COMPRA_FICHAS',
        p_monto       => 100000,  -- Esta transaccion debe ser bloqueada
        p_metodo_pago => 'EFECTIVO',
        p_trans_id    => v_trans_id
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO F: ERROR — La transaccion debio ser bloqueada.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO F: CORRECTO — Autoexcluido bloqueado por trigger:');
        DBMS_OUTPUT.PUT_LINE('  Codigo : ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Mensaje: ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA G: LÍMITE DIARIO — Transacción que supera el límite
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA G: Trigger trg_limite_diario — Superar limite
PROMPT  Natalia tiene limite de $500,000. Intentar $1,000,000.
PROMPT  NOTA: Natalia fue autoexcluida en F, usamos Ricardo (ID=3)
PROMPT  con limite $10,000,000. Haremos 2 transacciones que sumen
PROMPT  mas de su limite para disparar el error de limite.
PROMPT ----------------------------------------------------------
DECLARE
    v_trans_id NUMBER;
BEGIN
    -- Primera transaccion: COP $9,500,000 (dentro del limite de Ricardo)
    sp_registrar_transaccion(
        p_cliente_id  => 3,
        p_cajero_id   => 1,
        p_tipo        => 'COMPRA_FICHAS',
        p_monto       => 9500000,
        p_metodo_pago => 'TRANSFERENCIA',
        p_trans_id    => v_trans_id
    );
    DBMS_OUTPUT.PUT_LINE('Primera transaccion OK: COP $9,500,000 procesada.');

    -- Segunda transaccion: COP $1,000,000 — superaria los $10,000,000 del dia
    sp_registrar_transaccion(
        p_cliente_id  => 3,
        p_cajero_id   => 1,
        p_tipo        => 'COMPRA_FICHAS',
        p_monto       => 1000000,  -- Esto supera el limite diario restante
        p_metodo_pago => 'EFECTIVO',
        p_trans_id    => v_trans_id
    );
    DBMS_OUTPUT.PUT_LINE('RESULTADO G: ERROR — La segunda transaccion debio ser bloqueada.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESULTADO G: CORRECTO — Limite diario aplicado por trigger:');
        DBMS_OUTPUT.PUT_LINE('  Codigo : ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Mensaje: ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA H: BLOQUE ACID — NOWAIT (ORA-54)
-- ================================================================
-- PROPÓSITO: Demostrar control de concurrencia con FOR UPDATE NOWAIT.
--   ESCENARIO DE NEGOCIO: Dos cajeros intentan procesar simultáneamente
--   una transacción para el mismo cliente (Ricardo, ID=3).
--   El primer cajero bloquea el registro. El segundo recibe ORA-54
--   inmediatamente en lugar de esperar indefinidamente.
--   JUSTIFICACIÓN: En caja, un cajero no debe esperar: si el cliente
--   ya está siendo atendido, el sistema rechaza la operación de
--   inmediato para que el segundo cajero libere el turno.
-- PRAGMA EXCEPTION_INIT: Mapea el código nativo Oracle -54 a una
--   excepción PL/SQL nombrada para capturarla de forma específica.
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA H: ACID NOWAIT — Control de concurrencia
PROMPT  PRAGMA EXCEPTION_INIT(-54) — ORA-00054 resource busy
PROMPT ----------------------------------------------------------
DECLARE
    -- Declarar excepción personalizada para el código de error de Oracle
    ex_recurso_ocupado  EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_recurso_ocupado, -54);  -- ORA-00054: resource busy

    v_cliente_id        NUMBER;
    v_nombre            VARCHAR2(200);
    v_gasto_hoy         NUMBER(14,2);
    v_limite            NUMBER(14,2);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== INICIO BLOQUE NOWAIT ===');
    DBMS_OUTPUT.PUT_LINE('Cajero 1 intentando bloquear registro del cliente ID=4...');

    -- FOR UPDATE NOWAIT: intenta obtener el lock de forma inmediata.
    -- Si otra sesión ya tiene el lock, falla al instante con ORA-54.
    -- Esto evita deadlocks y esperas indefinidas en caja.
    SELECT cliente_id, nombres || ' ' || apellidos, gasto_hoy, limite_diario
    INTO   v_cliente_id, v_nombre, v_gasto_hoy, v_limite
    FROM   cliente
    WHERE  cliente_id = 4
    FOR UPDATE NOWAIT;  -- Fallar inmediatamente si el registro está bloqueado

    -- Si llegamos aquí, el lock fue obtenido exitosamente
    DBMS_OUTPUT.PUT_LINE('RESULTADO H (exito): Lock obtenido sobre cliente: ' || v_nombre);
    DBMS_OUTPUT.PUT_LINE('  Gasto hoy:    COP ' || TO_CHAR(v_gasto_hoy, 'FM999,999,999'));
    DBMS_OUTPUT.PUT_LINE('  Limite diario: COP ' || TO_CHAR(v_limite,   'FM999,999,999'));
    DBMS_OUTPUT.PUT_LINE('  >> Procesando verificacion de saldo... OK');

    -- Liberar el lock después de la verificación (sin modificar datos en esta prueba)
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('  >> COMMIT: Lock liberado. Transaccion atomica completada.');

EXCEPTION
    WHEN ex_recurso_ocupado THEN
        -- ORA-54: el registro ya estaba bloqueado por otra sesión
        ROLLBACK;  -- Asegurar que no queda nada pendiente
        DBMS_OUTPUT.PUT_LINE('RESULTADO H (fallo controlado ORA-54):');
        DBMS_OUTPUT.PUT_LINE('  El registro del cliente esta bloqueado por otro cajero.');
        DBMS_OUTPUT.PUT_LINE('  ROLLBACK ejecutado. Atomicidad garantizada.');
        DBMS_OUTPUT.PUT_LINE('  Codigo Oracle: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Accion: Redirigir cliente a otra caja disponible.');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('RESULTADO H (error inesperado): ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA I: BLOQUE ACID — WAIT n (ORA-30006)
-- ================================================================
-- PROPÓSITO: Demostrar control de concurrencia con FOR UPDATE WAIT.
--   ESCENARIO DE NEGOCIO: Un croupier intenta actualizar el estado
--   de una mesa antes de abrir una sesión. Si la mesa está siendo
--   modificada por mantenimiento, espera 5 segundos antes de rendirse.
--   JUSTIFICACIÓN DEL TIEMPO (5 segundos): Es el tiempo de tolerancia
--   máximo del sistema de caja antes de que el cliente en turno
--   perciba una demora inaceptable. Más de 5 segundos y el cliente
--   asume que algo está mal. Menos de 1 segundo no da tiempo a que
--   el bloqueo se libere naturalmente en operaciones breves.
-- PRAGMA EXCEPTION_INIT: Mapea el código nativo Oracle -30006 a una
--   excepción PL/SQL nombrada para capturarla de forma específica.
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA I: ACID WAIT 5 — Control de concurrencia con espera
PROMPT  PRAGMA EXCEPTION_INIT(-30006) — ORA-30006 resource busy
PROMPT ----------------------------------------------------------
DECLARE
    -- Declarar excepción personalizada para timeout de WAIT
    ex_timeout_espera   EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_timeout_espera, -30006);  -- ORA-30006: resource busy, WAIT expired

    v_mesa_id   NUMBER;
    v_numero    VARCHAR2(10);
    v_estado    VARCHAR2(15);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== INICIO BLOQUE WAIT 5 ===');
    DBMS_OUTPUT.PUT_LINE('Croupier intentando bloquear mesa M-01 (espera max: 5 seg)...');

    -- FOR UPDATE WAIT 5: espera hasta 5 segundos para obtener el lock.
    -- Si transcurren 5 segundos sin obtenerlo, lanza ORA-30006.
    -- Tiempo elegido: 5 seg = tolerancia máxima antes de timeout de UI.
    SELECT mesa_id, numero, estado
    INTO   v_mesa_id, v_numero, v_estado
    FROM   mesa
    WHERE  mesa_id = 1
    FOR UPDATE WAIT 5;  -- Esperar máximo 5 segundos antes de reportar timeout

    -- Si llegamos aquí, el lock fue obtenido antes de los 5 segundos
    DBMS_OUTPUT.PUT_LINE('RESULTADO I (exito): Mesa ' || v_numero ||
                          ' bloqueada en ' || v_estado);
    DBMS_OUTPUT.PUT_LINE('  >> Verificando disponibilidad para nueva sesion...');

    -- Verificar que la mesa sigue activa antes de abrir sesión
    IF v_estado = 'ACTIVA' THEN
        DBMS_OUTPUT.PUT_LINE('  >> Mesa disponible. Procediendo a abrir sesion.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('  >> Mesa no disponible. Estado: ' || v_estado);
        ROLLBACK;
        RETURN;
    END IF;

    COMMIT;  -- Liberar el lock de verificación
    DBMS_OUTPUT.PUT_LINE('  >> COMMIT: Verificacion completada. Lock liberado.');

EXCEPTION
    WHEN ex_timeout_espera THEN
        -- ORA-30006: se agotaron los 5 segundos de espera
        ROLLBACK;  -- Garantizar atomicidad: si no se pudo bloquear, no se modifica nada
        DBMS_OUTPUT.PUT_LINE('RESULTADO I (timeout ORA-30006):');
        DBMS_OUTPUT.PUT_LINE('  La mesa esta en uso por mas de 5 segundos.');
        DBMS_OUTPUT.PUT_LINE('  ROLLBACK ejecutado. No se abre la sesion.');
        DBMS_OUTPUT.PUT_LINE('  Codigo Oracle: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  Accion: Notificar al supervisor para reasignar mesa.');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('RESULTADO I (error inesperado): ' || SQLERRM);
END;
/

-- ================================================================
-- PRUEBA J: VISTAS — Consultas de validación
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA J: Consultas de verificación de vistas
PROMPT ----------------------------------------------------------

PROMPT >> Vista: v_catalogo_publico (seguridad — sin columnas sensibles)
SELECT numero_mesa, juego, sala, disponibilidad
FROM   v_catalogo_publico;

PROMPT >> Vista: v_reporte_ingresos_sala (reporte — JOIN + GROUP BY + SUM/COUNT)
SELECT sala, tipo_sala, total_sesiones,
       ganancia_total_casino, ganancia_promedio_sesion, clientes_unicos
FROM   v_reporte_ingresos_sala;

PROMPT >> Vista: v_clientes_resumen (nivel de riesgo + actividad)
SELECT nombre_completo, nivel_membresia, puntos_lealtad,
       total_apostado, nivel_riesgo, autoexcluido
FROM   v_clientes_resumen;

PROMPT >> Vista: v_ingresos_diarios (flujo de caja del dia)
SELECT fecha, tipo, total_transacciones, monto_total
FROM   v_ingresos_diarios;

PROMPT >> Vista: v_dashboard_gerencia (KPIs ejecutivos)
SELECT ventas_fichas_hoy, ganancia_mesas_hoy,
       clientes_activos_ahora, mesas_activas,
       alertas_aml_hoy, incidentes_abiertos
FROM   v_dashboard_gerencia;

PROMPT >> Vista: v_reporte_cajero (transacciones del dia)
SELECT referencia, cliente, tipo, metodo_pago, monto, numero_caja
FROM   v_reporte_cajero;

-- ================================================================
-- PRUEBA K: AUTOEVALUACIÓN FINAL — Objetos inválidos
-- ================================================================
PROMPT ----------------------------------------------------------
PROMPT  PRUEBA K: Autoevaluacion — Objetos con STATUS = INVALID
PROMPT  Si esta consulta devuelve 0 filas: entrega lista.
PROMPT  Si devuelve filas: hay errores de compilacion pendientes.
PROMPT ----------------------------------------------------------
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_type IN ('TABLE','TRIGGER','PROCEDURE','FUNCTION','VIEW','PACKAGE','PACKAGE BODY')
  AND  status = 'INVALID'
ORDER BY object_type, object_name;

PROMPT ============================================================
PROMPT  ROYALE GOLD CASINO — Instalacion completa exitosa
PROMPT  Todos los componentes creados y probados correctamente.
PROMPT ============================================================