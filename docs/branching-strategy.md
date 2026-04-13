# Estrategia de Branching

> Taller 1 — Construcción de pipelines en Cloud  
> Proyecto: [microservices-demo](https://github.com/juancasanov/microservices-demo)

---

## Índice

1. [Branching para desarrolladores — GitHub Flow](#branching-para-desarrolladores--github-flow)
2. [Branching para operaciones — Environment Branching](#branching-para-operaciones--environment-branching)
3. [Flujo combinado](#flujo-combinado)

---

## Branching para desarrolladores — GitHub Flow

### Descripción

**GitHub Flow** es una estrategia ligera y continua diseñada para equipos ágiles que hacen entregas frecuentes. Se basa en una única rama principal estable (`main`) y ramas de funcionalidad de corta duración (`feature/`).

### Estructura de ramas

```
main
 ├── feature/vote-validation
 ├── feature/result-websocket
 ├── feature/worker-retry-logic
 └── fix/kafka-connection-timeout
```

### Reglas

| Regla | Descripción |
|---|---|
| `main` es siempre desplegable | Todo lo que esté en `main` debe estar en estado funcional y probado |
| Ramas de corta duración | Las ramas `feature/` se crean, trabajan y fusionan en el menor tiempo posible |
| Pull Request obligatorio | Ningún cambio entra a `main` directamente — siempre via PR con revisión |
| CI antes del merge | El `deploy-pipeline.yml` debe pasar exitosamente antes de aprobar el PR |
| Nombrado descriptivo | `feature/<descripcion-corta>` o `fix/<descripcion-corta>` |

### Flujo paso a paso

```
1. Crear rama desde main
   git checkout main
   git pull origin main
   git checkout -b feature/nombre-funcionalidad

2. Desarrollar y hacer commits
   git add .
   git commit -m "feat: descripción del cambio"
   git push origin feature/nombre-funcionalidad

3. Abrir Pull Request hacia main
   → El deploy-pipeline.yml se activa automáticamente
   → Se ejecutan build + tests
   → Un compañero revisa el código

4. Merge a main (solo si el pipeline pasa y hay aprobación)
   → Se despliega automáticamente al ambiente de desarrollo
```

### Convención de commits

```
feat:     nueva funcionalidad
fix:      corrección de bug
chore:    tareas de mantenimiento
docs:     cambios en documentación
test:     adición o corrección de tests
refactor: refactorización sin cambio de comportamiento
```

### ¿Por qué GitHub Flow para desarrollo?

Es la estrategia ideal para este proyecto porque los tres microservicios (`vote`, `worker`, `result`) son independientes y pueden avanzar en paralelo. No se necesita una rama `develop` intermedia — los cambios validados van directo a `main` y el pipeline se encarga del despliegue.

---

## Branching para operaciones — Environment Branching

### Descripción

**Environment Branching** es una estrategia orientada a operaciones donde existe una rama dedicada por cada ambiente de despliegue. Los cambios de infraestructura avanzan de ambiente en ambiente mediante Pull Requests, garantizando que ningún cambio llegue a producción sin haber sido validado en etapas previas.

### Estructura de ramas

```
main (producción)
 └── staging (preproducción)
      └── develop (desarrollo/integración)
```

### Descripción de cada rama

| Rama | Ambiente | Acceso | Propósito |
|---|---|---|---|
| `develop` | Desarrollo | Push directo permitido | Integración continua, pruebas iniciales de infra |
| `staging` | Preproducción | Solo via Pull Request desde `develop` | Validación antes de producción |
| `main` | Producción | Solo via Pull Request desde `staging` | Infraestructura productiva estable |

### Reglas de protección de ramas

**Rama `staging`:**
- No se permiten pushes directos
- Requiere Pull Request aprobado desde `develop`
- El `infra-pipeline.yml` debe ejecutarse y pasar exitosamente
- Mínimo 1 aprobación requerida

**Rama `main`:**
- No se permiten pushes directos
- Requiere Pull Request aprobado desde `staging`
- El `infra-pipeline.yml` debe ejecutarse y pasar exitosamente
- Mínimo 1 aprobación requerida
- Solo miembros del equipo de operaciones pueden aprobar

### Flujo paso a paso

```
1. Cambio de infraestructura en develop
   git checkout develop
   git pull origin develop
   # Modificar archivos en /terraform o /infrastructure
   git add .
   git commit -m "infra: descripción del cambio"
   git push origin develop
   → infra-pipeline.yml corre terraform plan + apply en ambiente dev

2. Promover a staging (via Pull Request)
   → Abrir PR: develop → staging
   → infra-pipeline.yml valida el plan de Terraform en staging
   → Revisión y aprobación del equipo de operaciones
   → Merge: se aplican los cambios en el ambiente de staging

3. Promover a producción (via Pull Request)
   → Abrir PR: staging → main
   → infra-pipeline.yml valida el plan de Terraform en producción
   → Revisión y aprobación obligatoria
   → Merge: se aplican los cambios en producción
```

### Integración con Terraform

El `infra-pipeline.yml` detecta en qué rama se ejecuta y aplica la configuración del ambiente correspondiente:

```yaml
# Fragmento ilustrativo de infra-pipeline.yml
on:
  push:
    branches: [develop]
  pull_request:
    branches: [staging, main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Terraform Init
        run: terraform init
        working-directory: terraform/

      - name: Terraform Plan
        run: terraform plan
        working-directory: terraform/

      - name: Terraform Apply
        if: github.event_name == 'push'
        run: terraform apply -auto-approve
        working-directory: terraform/
```

### ¿Por qué Environment Branching para operaciones?

La infraestructura del proyecto (cluster Kubernetes, Kafka, PostgreSQL via Helm) requiere cambios controlados y auditables. Un error en Terraform aplicado directamente a producción puede tumbar todos los microservicios. Environment Branching garantiza que cada cambio de infraestructura pase por `develop` → `staging` → `main`, con una validación humana y automática en cada paso.

---

## Flujo combinado

Así se integran ambas estrategias en el día a día del equipo:

```
DESARROLLADORES (GitHub Flow)         OPERACIONES (Environment Branching)
──────────────────────────────        ────────────────────────────────────
feature/* ──PR──▶ main                develop ──PR──▶ staging ──PR──▶ main
                    │                                               │
                    ▼                                               ▼
             deploy-pipeline.yml                        infra-pipeline.yml
             (build · test · deploy)                    (terraform plan · apply)
                    │                                               │
                    ▼                                               ▼
             Kubernetes cluster  ◀─────────────────────────────────┘
```

- Los desarrolladores nunca tocan las ramas de ambiente (`staging`).
- El equipo de operaciones nunca toca las ramas `feature/`.
- Ambos pipelines despliegan al mismo cluster de Kubernetes pero con responsabilidades separadas.

---

