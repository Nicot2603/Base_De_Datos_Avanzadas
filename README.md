# 🎰 Royale Gold Casino — Sistema de Gestión de Base de Datos

> **Proyecto Final — Bases de Datos**
> Compatible con Oracle Database 21c XE / Oracle Live SQL (Free)

---

## SECCIÓN 1: PORTADA Y CONTEXTO CORPORATIVO

### Nombre de la Empresa

**Royale Gold Casino S.A.S.**
_"Donde cada dato es una apuesta segura."_

### Misión y Visión del Sistema

**Misión:** Royale Gold Casino S.A.S. opera una plataforma de gestión integral para casinos físicos que centraliza en una base de datos Oracle todos los procesos críticos del negocio: control de acceso de clientes, operación de mesas y máquinas tragamonedas, registro de transacciones de caja, programa de lealtad, gestión de torneos y cumplimiento regulatorio AML (Anti Lavado de Dinero). El sistema garantiza que cada operación sea atómica, trazable y conforme con la normativa de la Unidad de Información y Análisis Financiero (UIAF) de Colombia, eliminando la dependencia de lógica de negocio dispersa en aplicaciones externas.

**Visión:** Ser la solución de referencia en gestión de datos para la industria del entretenimiento regulado en Colombia, ofreciendo una arquitectura de base de datos que soporte el crecimiento de la operación sin sacrificar integridad, seguridad ni trazabilidad de la información.

### Integrantes del Equipo

| Nombre Completo               | Código Estudiantil | Rol en el Proyecto                   |
| ----------------------------- | ------------------ | ------------------------------------ |
| Carol Nicol Clavijo Bonilla   | 1028663315         | Arquitecta de Datos y Modelado ER    |
| Daniel Alejandro Marson Rosas | 5671988            | Desarrollador PL/SQL y Control ACID  |
| Adrian David Bravo Montoya    | 1019902373         | Líder de QA y Pruebas de Integración |

---

## SECCIÓN 2: LÓGICA DE NEGOCIO Y REQUERIMIENTOS

### 2.1 Reglas de Negocio del Sistema

El sistema Royale Gold Casino implementa las siguientes reglas que gobiernan toda la operación del casino:

**Regla 1 — Mayoría de edad obligatoria:**
Ningún cliente menor de 18 años puede ser registrado en el sistema ni realizar transacciones. Esta regla está respaldada por la Ley 643 de 2001 (Ley del Monopolio Rentístico de Juegos de Suerte y Azar en Colombia) y se implementa directamente en el motor de base de datos para que no pueda ser eludida desde ninguna capa de aplicación.

**Regla 2 — Control de límite diario de gasto (Juego Responsable):**
Cada cliente tiene asignado un tope máximo de gasto diario (por defecto COP $5,000,000). El sistema no permite que la suma de transacciones de compra de fichas y depósitos de un mismo cliente supere ese límite en un día calendario. El contador se resetea automáticamente en la primera transacción de cada nuevo día.

**Regla 3 — Autoexclusión total:**
Un cliente que solicite autoexclusión queda bloqueado de forma permanente para cualquier transacción de gasto (compra de fichas o depósito). El bloqueo opera desde el trigger antes de que la transacción llegue a procesarse en caja, haciendo imposible que el cajero cometa el error de atenderlo por descuido.

**Regla 4 — Alerta automática AML:**
Toda transacción igual o superior a COP $10,000,000 genera automáticamente un incidente de tipo AML en la tabla de incidentes, con los datos del cliente y la transacción. Este umbral corresponde al monto de reporte obligatorio establecido por la UIAF Colombia, y el proceso es completamente automático, sin depender de que ningún empleado lo reporte manualmente.

**Regla 5 — Integridad de mesas de juego:**
No se puede iniciar una sesión de juego en una mesa que no esté en estado `ACTIVA`. Mesas en `MANTENIMIENTO` o `INACTIVA` rechazan cualquier intento de apertura de sesión antes de que el registro llegue a la tabla, evitando inconsistencias operativas.

**Regla 6 — Seguridad financiera — datos sensibles del casino:**
Los asesores comerciales, croupiers y personal de caja no tienen acceso a la ventaja estadística de las máquinas (porcentaje de pago RTP) ni a los rangos de apuesta de las mesas. Esta información, si fuera accesible, permitiría a empleados o clientes calcular estrategias que minimizan la ventaja de la casa.

---

### 2.2 Tabla de Mapeo: Requerimientos vs. Objetos SQL

| Requerimiento del Negocio                                                     | Componente Técnico                      | Objeto Específico en el Código                                          |
| ----------------------------------------------------------------------------- | --------------------------------------- | ----------------------------------------------------------------------- |
| Prohibir registro de menores de 18 años                                       | TRIGGER BEFORE INSERT                   | `trg_cliente_edad_minima`                                               |
| Bloquear gasto que supere el límite diario del cliente                        | TRIGGER BEFORE INSERT                   | `trg_limite_diario`                                                     |
| Bloquear transacciones de clientes autoexcluidos                              | TRIGGER BEFORE INSERT                   | `trg_limite_diario` (mismo trigger, segunda validación)                 |
| Generar alerta AML automática en transacciones ≥ $10M                         | TRIGGER AFTER INSERT                    | `trg_alerta_aml`                                                        |
| Impedir sesiones en mesas fuera de servicio                                   | TRIGGER BEFORE INSERT                   | `trg_validar_mesa_activa`                                               |
| Acumular puntos de lealtad por cada compra de fichas                          | TRIGGER AFTER INSERT                    | `trg_acumular_puntos`                                                   |
| Calcular premio de torneo automáticamente (80% del pozo)                      | TRIGGER BEFORE INSERT/UPDATE            | `trg_calcular_premio_torneo`                                            |
| Registrar todo cambio en datos de clientes                                    | TRIGGER AFTER INSERT/UPDATE/DELETE      | `trg_auditoria_cliente`                                                 |
| Evitar bloqueos infinitos cuando dos cajeros atienden al mismo cliente        | Control de Concurrencia ACID            | Bloque PL/SQL con `FOR UPDATE NOWAIT` + `PRAGMA EXCEPTION_INIT(-54)`    |
| Dar tiempo de tolerancia razonable antes de declarar un recurso no disponible | Control de Concurrencia ACID            | Bloque PL/SQL con `FOR UPDATE WAIT 5` + `PRAGMA EXCEPTION_INIT(-30006)` |
| Registrar nuevos clientes con validación de datos                             | STORED PROCEDURE                        | `sp_registrar_cliente`                                                  |
| Procesar transacciones de caja con atomicidad garantizada                     | STORED PROCEDURE                        | `sp_registrar_transaccion`                                              |
| Abrir y cerrar sesiones de juego en mesas                                     | STORED PROCEDURE                        | `sp_abrir_sesion_mesa`, `sp_cerrar_sesion_mesa`                         |
| Ocultar RTP y rangos de apuesta al personal y clientes                        | Vista de Seguridad                      | `v_catalogo_publico`                                                    |
| Responder la pregunta de rentabilidad por sala para la junta directiva        | Vista de Reporte                        | `v_reporte_ingresos_sala`                                               |
| Calcular nivel de riesgo de ludopatía por cliente                             | FUNCTION                                | `fn_nivel_riesgo_cliente`                                               |
| Calcular ganancia total del casino en un período                              | FUNCTION                                | `fn_ganancia_periodo`                                                   |
| Controlar acceso por rol (cajero, croupier, seguridad, admin)                 | PACKAGE + PROCEDURE + Vistas con filtro | `pkg_contexto_casino`, `sp_login`, `sp_logout`                          |

---

## SECCIÓN 3: MODELADO — DIAGRAMA ER Y DICCIONARIO DE DATOS

### 3.1 Diagrama Entidad-Relación

```
CARGO ──────────────< EMPLEADO
                          │
                  ┌───────┴────────┐
                  │                │
               CAJERO          SESION_MESA >──── MESA >──── TIPO_JUEGO
                  │                │                │
                  │            CLIENTE          SALA <──── MAQUINA
                  │                │                │
             TRANSACCION       SESION_MAQUINA  TORNEO
                  │                │               │
           MOVIMIENTO_PUNTOS   INCIDENTE    INSCRIPCION_TORNEO
                  │
           AUDITORIA_LOG
                  │
           USUARIOS_SISTEMA
```

> **Nota para la entrega:** Incluir el diagrama ER generado desde Oracle SQL Developer Data Modeler o dbdiagram.io como imagen `docs/diagrama_ER.png`. El esquema textual arriba es la representación de referencia para este README.

**Cardinalidades principales:**

- `cargo` 1 → N `empleado` — Un cargo puede tener muchos empleados.
- `empleado` 1 → 1 `cajero` — Un empleado solo puede operar una caja.
- `cliente` 1 → N `transaccion` — Un cliente puede tener muchas transacciones.
- `cliente` 1 → N `sesion_mesa` — Un cliente puede jugar en muchas mesas.
- `mesa` 1 → N `sesion_mesa` — Una mesa puede tener muchas sesiones a lo largo del tiempo.
- `sala` 1 → N `mesa` — Una sala contiene múltiples mesas.
- `sala` 1 → N `maquina` — Una sala contiene múltiples máquinas.
- `torneo` 1 → N `inscripcion_torneo` — Un torneo tiene muchos inscritos.
- `cliente` 1 → N `movimiento_puntos` — Un cliente tiene un historial de puntos.
- `cliente` 1 → N `incidente` — Un cliente puede estar involucrado en varios incidentes.
- `auditoria_log` recibe registros de triggers de `cliente`, `transaccion` y `usuarios_sistema`.

---

### 3.2 Diccionario de Datos

#### Tabla: `cargo`

| Columna        | Tipo          | Restricción         | Descripción                            |
| -------------- | ------------- | ------------------- | -------------------------------------- |
| `cargo_id`     | NUMBER(6)     | PK, IDENTITY        | Identificador único del cargo          |
| `nombre`       | VARCHAR2(100) | NOT NULL            | Nombre del cargo (CEO, Croupier, etc.) |
| `salario_base` | NUMBER(12,2)  | NOT NULL, CHECK > 0 | Salario base mensual en COP            |
| `descripcion`  | VARCHAR2(500) | —                   | Descripción de responsabilidades       |

#### Tabla: `empleado`

| Columna             | Tipo          | Restricción                                    | Descripción                      |
| ------------------- | ------------- | ---------------------------------------------- | -------------------------------- |
| `empleado_id`       | NUMBER(8)     | PK, IDENTITY                                   | Identificador único del empleado |
| `cedula`            | VARCHAR2(20)  | NOT NULL, UNIQUE                               | Documento de identidad           |
| `nombres`           | VARCHAR2(100) | NOT NULL                                       | Nombres del empleado             |
| `apellidos`         | VARCHAR2(100) | NOT NULL                                       | Apellidos del empleado           |
| `cargo_id`          | NUMBER(6)     | FK → cargo                                     | Cargo que desempeña              |
| `fecha_ingreso`     | DATE          | NOT NULL                                       | Fecha de vinculación             |
| `email_corporativo` | VARCHAR2(150) | —                                              | Correo institucional             |
| `turno`             | VARCHAR2(10)  | CHECK IN ('MAÑANA','TARDE','NOCHE','ROTATIVO') | Turno de trabajo                 |
| `activo`            | NUMBER(1)     | DEFAULT 1, CHECK IN (0,1)                      | Estado laboral activo/inactivo   |

#### Tabla: `cliente`

| Columna            | Tipo          | Restricción                | Descripción                           |
| ------------------ | ------------- | -------------------------- | ------------------------------------- |
| `cliente_id`       | NUMBER(10)    | PK, IDENTITY               | Identificador único del cliente       |
| `cedula`           | VARCHAR2(20)  | NOT NULL, UNIQUE           | Documento de identidad                |
| `nombres`          | VARCHAR2(100) | NOT NULL                   | Nombres del cliente                   |
| `apellidos`        | VARCHAR2(100) | NOT NULL                   | Apellidos del cliente                 |
| `fecha_nacimiento` | DATE          | NOT NULL                   | Validada por trigger (mínimo 18 años) |
| `email`            | VARCHAR2(150) | UNIQUE                     | Correo electrónico                    |
| `nivel_membresia`  | VARCHAR2(10)  | DEFAULT 'BRONCE', CHECK    | Nivel del programa de lealtad         |
| `puntos_lealtad`   | NUMBER(10)    | DEFAULT 0                  | Puntos acumulados                     |
| `autoexcluido`     | NUMBER(1)     | DEFAULT 0, CHECK IN (0,1)  | Flag de autoexclusión voluntaria      |
| `limite_diario`    | NUMBER(14,2)  | DEFAULT 5000000, CHECK > 0 | Tope de gasto diario en COP           |
| `gasto_hoy`        | NUMBER(14,2)  | DEFAULT 0, CHECK >= 0      | Gasto acumulado en el día actual      |

#### Tabla: `mesa`

| Columna         | Tipo         | Restricción                                    | Descripción                            |
| --------------- | ------------ | ---------------------------------------------- | -------------------------------------- |
| `mesa_id`       | NUMBER(8)    | PK, IDENTITY                                   | Identificador único                    |
| `numero`        | VARCHAR2(10) | NOT NULL, UNIQUE                               | Código visible en la mesa (M-01, etc.) |
| `sala_id`       | NUMBER(6)    | FK → sala                                      | Sala donde se ubica                    |
| `tipo_juego_id` | NUMBER(6)    | FK → tipo_juego                                | Juego que se practica en la mesa       |
| `apuesta_min`   | NUMBER(12,2) | CHECK > 0                                      | Apuesta mínima permitida               |
| `apuesta_max`   | NUMBER(12,2) | CHECK > apuesta_min                            | Apuesta máxima permitida               |
| `estado`        | VARCHAR2(15) | CHECK IN ('ACTIVA','INACTIVA','MANTENIMIENTO') | Estado operativo                       |

#### Tabla: `transaccion`

| Columna          | Tipo         | Restricción                                                              | Descripción                       |
| ---------------- | ------------ | ------------------------------------------------------------------------ | --------------------------------- |
| `transaccion_id` | NUMBER(15)   | PK, IDENTITY                                                             | Identificador único               |
| `cliente_id`     | NUMBER(10)   | FK → cliente                                                             | Cliente que realiza la operación  |
| `cajero_id`      | NUMBER(6)    | FK → cajero                                                              | Cajero que procesa                |
| `tipo`           | VARCHAR2(20) | CHECK IN ('COMPRA_FICHAS','CANJE_FICHAS','DEPOSITO','RETIRO','PREMIO')   | Tipo de operación                 |
| `monto`          | NUMBER(14,2) | CHECK > 0                                                                | Valor en COP                      |
| `metodo_pago`    | VARCHAR2(20) | CHECK IN ('EFECTIVO','TARJETA_DEBITO','TARJETA_CREDITO','TRANSFERENCIA') | Medio de pago                     |
| `fecha_hora`     | TIMESTAMP    | DEFAULT SYSTIMESTAMP                                                     | Momento exacto de la operación    |
| `referencia`     | VARCHAR2(80) | —                                                                        | Código único generado por trigger |
| `revertida`      | NUMBER(1)    | DEFAULT 0, CHECK IN (0,1)                                                | Flag de anulación                 |

#### Tabla: `sesion_mesa`

| Columna           | Tipo         | Restricción          | Descripción                           |
| ----------------- | ------------ | -------------------- | ------------------------------------- |
| `sesion_id`       | NUMBER(15)   | PK, IDENTITY         | Identificador único                   |
| `cliente_id`      | NUMBER(10)   | FK → cliente         | Jugador en la sesión                  |
| `mesa_id`         | NUMBER(8)    | FK → mesa            | Mesa donde se juega                   |
| `empleado_id`     | NUMBER(8)    | FK → empleado        | Croupier asignado                     |
| `fecha_inicio`    | TIMESTAMP    | DEFAULT SYSTIMESTAMP | Hora de inicio de la sesión           |
| `fecha_fin`       | TIMESTAMP    | —                    | NULL mientras la sesión está activa   |
| `apuesta_total`   | NUMBER(14,2) | DEFAULT 0            | Total apostado durante la sesión      |
| `ganancia_casino` | NUMBER(14,2) | DEFAULT 0            | Ganancia neta del casino en la sesión |

#### Tabla: `auditoria_log`

| Columna          | Tipo           | Restricción                           | Descripción                          |
| ---------------- | -------------- | ------------------------------------- | ------------------------------------ |
| `log_id`         | NUMBER(15)     | PK, IDENTITY                          | Identificador único del registro     |
| `tabla_afectada` | VARCHAR2(50)   | NOT NULL                              | Nombre de la tabla modificada        |
| `operacion`      | VARCHAR2(10)   | CHECK IN ('INSERT','UPDATE','DELETE') | Tipo de operación registrada         |
| `registro_id`    | NUMBER(15)     | —                                     | ID del registro modificado           |
| `usuario_bd`     | VARCHAR2(50)   | DEFAULT USER                          | Usuario de base de datos que ejecutó |
| `fecha_hora`     | TIMESTAMP      | DEFAULT SYSTIMESTAMP                  | Momento exacto del evento            |
| `detalle`        | VARCHAR2(1000) | —                                     | Descripción del cambio realizado     |

---

## SECCIÓN 4: ARQUITECTURA TRANSACCIONAL — JUSTIFICACIÓN ACID

### Análisis de Concurrencia — El Peor Escenario Posible

Imaginar el siguiente escenario en hora pico un sábado en la noche: dos cajeros en cajas diferentes (CAJA-01 y CAJA-02) reciben simultáneamente a dos personas distintas que quieren comprar fichas para el mismo cliente VIP (Ricardo Salcedo, cliente_id = 3), quizás porque el cliente envió a un acompañante a una segunda caja mientras él espera en otra.

Si ambas transacciones se ejecutan en paralelo sin ningún mecanismo de control, las dos leerían el mismo valor de `gasto_hoy` (digamos COP $8,000,000) y las dos concluirían que la compra de COP $1,500,000 está dentro del límite diario de COP $10,000,000. Ambas se aprobarían, el `gasto_hoy` quedaría en un valor inconsistente y el cliente habría superado su límite sin que el sistema lo detectara, violando la regulación de juego responsable.

### Justificación del NOWAIT (ORA-54) — Caja de Casino

En el contexto de caja de un casino, la inmediatez es crítica. Un cajero tiene al cliente de frente en una ventanilla física; si el sistema tarda más de dos o tres segundos en responder, el cliente y el cajero interpretan que algo está mal. Por esta razón, el bloque `FOR UPDATE NOWAIT` es la elección correcta para las operaciones de verificación de saldo en caja: si el registro ya está bloqueado por otra sesión, el sistema falla inmediatamente con ORA-54 y el cajero puede redirigir al cliente a otra caja disponible sin espera. El uso de `PRAGMA EXCEPTION_INIT(-54)` en lugar de `WHEN OTHERS` permite dar un mensaje específico y accionable al operador ("el registro está bloqueado, dirija al cliente a otra caja") en lugar de un mensaje genérico que no dice qué hacer.

### Justificación del WAIT 5 (ORA-30006) — Verificación de Mesa

El bloque `FOR UPDATE WAIT 5` se usa en el escenario de verificación de disponibilidad de mesa antes de abrir una sesión de juego. En este caso, el croupier no está frente a un cliente en ventanilla sino gestionando una mesa; una espera de 5 segundos es razonable porque la operación que mantiene el lock (por ejemplo, un sistema de mantenimiento actualizando el estado de la mesa) es normalmente muy breve. Si después de 5 segundos el lock no se liberó, es señal de que hay un problema de operación mayor y el sistema lanza ORA-30006, lo que dispara una notificación al supervisor para reasignar la mesa. Se eligieron 5 segundos porque es el tiempo de timeout estándar de la mayoría de interfaces de usuario antes de mostrar un error al operador.

### Defensa del Uso de Excepciones Especializadas

El uso de `PRAGMA EXCEPTION_INIT` con los códigos `-54` y `-30006` en lugar del genérico `WHEN OTHERS` responde a tres razones técnicas concretas:

**1. Mensajes accionables:** `WHEN OTHERS` captura absolutamente cualquier error, incluyendo errores de sintaxis, fallas de red o problemas de hardware. Al capturar específicamente el -54 o -30006, el bloque PL/SQL sabe con certeza qué pasó y puede mostrar un mensaje que le diga al operador exactamente qué acción tomar, no solo que "algo salió mal".

**2. Relanzamiento correcto de otros errores:** Al tener un handler específico para los errores de concurrencia y un `WHEN OTHERS` separado para el resto, los errores no relacionados con concurrencia (como una FK violada o un CHECK constraint fallido) se relanzarán correctamente con su propio código y mensaje, en lugar de quedar silenciados dentro del handler de concurrencia.

**3. Trazabilidad y auditoría:** El `DBMS_OUTPUT` dentro del handler específico puede registrar exactamente el tipo de conflicto de concurrencia que ocurrió, lo que es útil para detectar patrones de uso concurrente problemático en la operación del casino.

---

## SECCIÓN 5: SEGURIDAD Y REPORTERÍA — VISTAS

### Estrategia de Seguridad — `v_catalogo_publico`

La vista `v_catalogo_publico` es la interfaz que se expone a clientes en pantallas del casino y a asesores comerciales. Las siguientes columnas fueron excluidas deliberadamente:

**`apuesta_min` y `apuesta_max` (tabla `mesa`):** Aunque estos datos podrían parecer informativos para el cliente, su exposición combinada con el conocimiento del tipo de juego permitiría a jugadores avanzados calcular la ventaja de la casa por mesa y seleccionar sistemáticamente las mesas con menor ventaja para el casino. En su lugar, la vista expone únicamente la disponibilidad de la mesa.

**`porcentaje_pago` — RTP (tabla `maquina`):** El Return to Player (RTP) es el dato más sensible de las máquinas tragamonedas. Es la proporción estadística del dinero apostado que la máquina devuelve al jugador a largo plazo. Si este porcentaje fuera público, los jugadores con conocimiento estadístico seleccionarían exclusivamente las máquinas con RTP más alto, alterando los ingresos proyectados del casino de forma sistemática. La Ley 643 de 2001 exige que el RTP sea reportado a Coljuegos pero no obliga a publicarlo al jugador, lo que da fundamento legal a esta restricción.

### Pregunta de Negocio Resuelta — `v_reporte_ingresos_sala`

La vista `v_reporte_ingresos_sala` responde la siguiente pregunta estratégica a la junta directiva:

> _"¿Cuál sala del casino genera más ganancia neta para la empresa, cuántos clientes únicos atrae, cuál es la ganancia promedio por sesión y cuántas mesas tiene activas — información que permite al Director de Operaciones decidir dónde invertir en expansión, qué salas requieren revisión de su mix de juegos y cuál es la eficiencia real de cada piso del casino?"_

La vista entrega esta respuesta con un único `SELECT`, sin que la junta necesite cruzar tablas manualmente, y ordena los resultados de mayor a menor ganancia para que la sala más rentable aparezca primero.

---

## SECCIÓN 6: CONCLUSIONES Y BUENAS PRÁCTICAS

### Ventajas de Delegar la Lógica al Servidor de Base de Datos

La experiencia de construir este sistema dejó una lección central: **la base de datos es el único punto de control que no se puede eludir**. Durante el desarrollo se identificaron al menos tres escenarios donde delegar la lógica al servidor fue la única solución robusta:

La validación de mayoría de edad, por ejemplo, podría haberse implementado en una aplicación web o en un formulario de registro. Pero si alguien conecta directamente con SQL Developer o un script de Python y hace un `INSERT` directo en la tabla `cliente`, la validación de la aplicación no aplica. El trigger `trg_cliente_edad_minima` sí aplica porque vive en el motor, no en la aplicación.

Lo mismo ocurre con el límite diario de gasto: un cajero podría tener un mal día, ignorar la advertencia en pantalla o usar una herramienta diferente. El trigger `trg_limite_diario` garantiza que el límite se respete sin importar desde dónde venga el `INSERT`.

Finalmente, la acumulación de puntos y el ascenso de membresía a través de `trg_acumular_puntos` eliminó la necesidad de escribir esa lógica en cada módulo de la aplicación que procesara una compra. El servidor la ejecuta una sola vez, de forma consistente, en todos los casos.

### Impacto del Estándar de Nomenclatura

Trabajar con el estándar definido en la guía (tablas en minúsculas con guion bajo, PKs con el patrón `nombre_tabla_id`, FKs con prefijo `fk_`, triggers con prefijo `trg_`, procedimientos con prefijo `sp_`) demostró su valor en la integración del script final. Cuando los tres integrantes del equipo generaron sus bloques de código por separado, las FKs referenciaban correctamente las PKs de las otras tablas sin necesidad de revisar cuál era el nombre exacto de cada columna — el nombre mismo lo decía. Por ejemplo, `fk_trans_cliente` que referencia `cliente_id` en `transaccion` es auto-descriptivo y no requiere consultar el DDL para entender la relación. Esto redujo significativamente los errores de integración al unificar el script final.

---

## Instrucciones de Ejecución

### Requisitos

- Oracle Database 21c XE o superior, **o** Oracle Live SQL (free.oracle.com)
- SQL\*Plus, SQL Developer, o el editor de Oracle Live SQL
- Usuario con permisos para crear tablas, triggers, procedures, functions y views

### Pasos para ejecutar

```sql
-- 1. Conectarse a Oracle Live SQL o a la instancia XE
-- 2. Abrir el archivo royale_gold_casino_final.sql
-- 3. Ejecutar el script completo (F5 o Run Script)
-- 4. Verificar que no hay objetos inválidos:

SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_type IN ('TABLE','TRIGGER','PROCEDURE','FUNCTION','VIEW','PACKAGE','PACKAGE BODY')
  AND  status = 'INVALID';

-- Si la consulta devuelve 0 filas: instalación exitosa.
```

### Estructura del repositorio

```
royale-gold-casino/
├── README.md                          ← Este archivo
├── royale_gold_casino_final.sql       ← Script principal (el que se evalúa)
└── docs/
    └── diagrama_ER.png                ← Diagrama entidad-relación
```

### Credenciales del sistema de roles simulado

| Usuario           | Contraseña       | Rol          |
| ----------------- | ---------------- | ------------ |
| `admin_casino`    | `Admin2025!`     | CASINO_ADMIN |
| `cajero_paola`    | `Cajero2025!`    | CAJERO       |
| `croupier_andres` | `Croupier2025!`  | CROUPIER     |
| `seguridad_1`     | `Seguridad2025!` | SEGURIDAD    |

```sql
-- Ejemplo de uso del sistema de roles:
EXEC sp_login('cajero_paola', 'Cajero2025!');
SELECT * FROM v_cajero_transacciones_hoy;
EXEC sp_logout;
```

---
