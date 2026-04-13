# Patrones de Diseño en la Nube

> Taller 1 — Construcción de pipelines en Cloud  
> Proyecto: [microservices-demo](https://github.com/juancasanov/microservices-demo)  
> Metodología ágil: Scrum

---

## Índice

1. [Patrón 1: Event-Driven Messaging](#patrón-1-event-driven-messaging)
2. [Patrón 2: Sidecar Pattern](#patrón-2-sidecar-pattern)
3. [Relación entre patrones](#relación-entre-patrones)

---

## Patrón 1: Event-Driven Messaging

### Descripción

El patrón **Event-Driven Messaging** establece que los componentes de un sistema se comunican mediante la publicación y consumo de eventos a través de un intermediario (broker), en lugar de llamarse directamente entre sí. Esto elimina el acoplamiento directo entre servicios.

### ¿Dónde aplica en este proyecto?

```
[Vote Service] ──publica evento──▶ [Kafka: topic "votes"] ──consume──▶ [Worker Service] ──persiste──▶ [PostgreSQL]
                                                                                                              │
                                                                                                    [Result Service] ◀── lee
```

| Componente | Rol en el patrón | Tecnología |
|---|---|---|
| `vote/` | **Productor** — publica evento `VoteCast` al topic `votes` | Java |
| Kafka | **Broker** — almacena y enruta eventos de forma asíncrona | Apache Kafka (Bitnami Helm) |
| `worker/` | **Consumidor** — procesa el evento y escribe en la base de datos | Go |
| PostgreSQL | **Estado persistente** — almacén de resultados | PostgreSQL (Bitnami Helm) |
| `result/` | **Lector** — consulta la base de datos para mostrar resultados en tiempo real | Node.js |

### Funcionamiento paso a paso

1. Un usuario emite un voto desde el frontend Java (`vote/`).
2. El servicio Vote publica un mensaje en el **topic `votes`** de Kafka. En este momento su responsabilidad termina — no espera respuesta.
3. Kafka retiene el mensaje en su log hasta que el consumidor lo procese.
4. El **Worker** (Go) consume el mensaje del topic, lo valida y lo inserta en PostgreSQL.
5. El **Result Service** (Node.js) consulta PostgreSQL y muestra los resultados actualizados.

### Beneficios aplicados al proyecto

**Desacoplamiento temporal:** El `vote/` y el `worker/` no necesitan estar disponibles al mismo tiempo. Si el Worker se reinicia, Kafka conserva los mensajes y los entrega cuando vuelva.

**Tolerancia a fallos:** Si el Worker falla, el mensaje permanece en el topic. Puede ser reintentado sin pérdida de datos.

**Escalabilidad independiente:** Ante un pico de votaciones se pueden escalar múltiples réplicas del Worker consumiendo del mismo topic en paralelo, sin modificar el servicio Vote ni el Result.

**Trazabilidad:** El log de Kafka actúa como registro histórico de todos los eventos emitidos.

---

## Patrón 2: Sidecar Pattern

### Descripción

El patrón **Sidecar** consiste en acompañar cada componente principal con un proceso auxiliar que extiende su comportamiento sin modificar su código. En este proyecto se aplica al pipeline de CI/CD: cada responsabilidad (despliegue de aplicación e infraestructura) tiene su propio workflow autónomo en `.github/workflows/`.

### ¿Dónde aplica en este proyecto?

Los dos workflows en `.github/workflows/` actúan como sidecars del sistema completo:

```
Código de servicios  ←───  deploy-pipeline.yml   (build · test · push · deploy de los 3 servicios)
Infraestructura      ←───  infra-pipeline.yml     (terraform plan · terraform apply)
```

Cada workflow es **autónomo**: tiene su propio ciclo de activación, sus propias responsabilidades y puede fallar o ejecutarse sin afectar al otro.

### Descripción de los workflows

#### `deploy-pipeline.yml` — Sidecar de despliegue de aplicación

Se encarga de construir, testear y desplegar los tres microservicios (`vote`, `worker`, `result`) hacia el cluster de Kubernetes. Sus etapas principales son:

- Build de imágenes Docker para cada servicio
- Ejecución de tests
- Push al registry (Docker Hub)
- Deploy al cluster mediante Helm

#### `infra-pipeline.yml` — Sidecar de infraestructura

Se encarga exclusivamente de provisionar y actualizar la infraestructura cloud mediante Terraform. Sus etapas principales son:

- `terraform init` — inicialización del estado remoto
- `terraform plan` — previsualización de cambios
- `terraform apply` — aplicación de cambios al cluster de Kubernetes

### Beneficios aplicados al proyecto

**Separación de responsabilidades:** El código de la aplicación y la infraestructura tienen ciclos de vida distintos. Un cambio en el código de `vote` no tiene por qué modificar la infraestructura, y viceversa.

**Fallos aislados:** Si `infra-pipeline.yml` falla (por ejemplo, un error de Terraform), `deploy-pipeline.yml` puede seguir funcionando para despliegues de código.

**Equipos independientes:** El equipo de desarrollo puede trabajar sobre `deploy-pipeline.yml` sin necesitar permisos ni conocimiento de Terraform. El equipo de operaciones gestiona `infra-pipeline.yml` de forma autónoma.

**Auditoría clara:** El historial de GitHub Actions muestra por separado cuándo hubo cambios de infraestructura vs. cambios de aplicación.

---

## Relación entre patrones

```
Desarrollo           CI/CD (Sidecar)                  Producción (Event-Driven)
────────────────────────────────────────────────────────────────────────────────────
vote/   ──┐
worker/ ──┼──▶  deploy-pipeline.yml ──▶ K8s  ──▶  Vote  ──▶ Kafka ──▶ Worker ──▶ PostgreSQL
result/ ──┘                                         Result ◀──────────────────────────┘
infra/  ──────▶  infra-pipeline.yml  ──▶ Terraform ──▶ Kubernetes cluster
```

- El **Sidecar Pattern** garantiza que aplicación e infraestructura se gestionen con pipelines independientes.
- El **Event-Driven Messaging** garantiza que, en producción, los servicios se comuniquen de forma asíncrona y desacoplada a través de Kafka.

---