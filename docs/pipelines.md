# Pipelines CI/CD

> Taller 1 — Construcción de pipelines en Cloud  
> Proyecto: [microservices-demo](https://github.com/juancasanov/microservices-demo)

---

## Índice

1. [Visión general](#visión-general)
2. [deploy-pipeline.yml — Pipeline de desarrollo](#deploy-pipelineyml--pipeline-de-desarrollo)
3. [infra-pipeline.yml — Pipeline de infraestructura](#infra-pipelineyml--pipeline-de-infraestructura)
4. [Secrets requeridos](#secrets-requeridos)

---

## Visión general

El proyecto cuenta con dos pipelines en `.github/workflows/`, cada uno con una responsabilidad clara y separada:

```
Evento (push / PR)
       │
       ├──▶ deploy-pipeline.yml  ──▶ Build · Test · Push · Deploy (servicios)
       │
       └──▶ infra-pipeline.yml   ──▶ Terraform Plan · Apply (infraestructura)
```

Esta separación sigue el **Sidecar Pattern**: cada pipeline tiene su propio ciclo de vida y puede fallar o ejecutarse de forma independiente sin afectar al otro.

---

## deploy-pipeline.yml — Pipeline de desarrollo

### Responsabilidad

Construir, testear, empaquetar y desplegar los tres microservicios (`vote`, `worker`, `result`) al cluster de Kubernetes cada vez que hay un cambio en el código de la aplicación.

### Activación

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

### Etapas

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Checkout  │───▶│  Build imgs │───▶│    Tests    │───▶│  Push imgs  │
│   del repo  │    │  (x3 svcs)  │    │  (x3 svcs)  │    │  Docker Hub │
└─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘
                                                                  │
                                                                  ▼
                                                         ┌─────────────────┐
                                                         │  Deploy a K8s   │
                                                         │  (Helm upgrade) │
                                                         └─────────────────┘
```

### Descripción de cada etapa

**1. Checkout** — descarga el código del repositorio en el runner de GitHub Actions.

**2. Build de imágenes Docker** — construye una imagen Docker para cada uno de los tres servicios usando sus respectivos `Dockerfile`:
- `vote/Dockerfile` → imagen `vote:sha`
- `worker/Dockerfile` → imagen `worker:sha`
- `result/Dockerfile` → imagen `result:sha`

Cada imagen se etiqueta con el SHA del commit para trazabilidad completa.

**3. Tests** — ejecuta los tests de cada servicio en su entorno correspondiente:
- Vote (Java): `mvn test`
- Worker (Go): `go test ./...`
- Result (Node.js): `npm test`

Si algún test falla, el pipeline se detiene y no continúa al paso de push ni deploy.

**4. Push a Docker Hub** — sube las tres imágenes construidas al registry. Requiere los secrets `DOCKER_USERNAME` y `DOCKER_PASSWORD`.

**5. Deploy a Kubernetes** — aplica los manifiestos de Kubernetes usando `helm upgrade --install` para cada servicio, apuntando a las nuevas imágenes recién publicadas.

### Script de referencia

```yaml
name: Deploy Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-test-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Login to Docker Hub
        run: echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin

      - name: Build images
        run: |
          docker build -t ${{ secrets.DOCKER_USERNAME }}/vote:${{ github.sha }}   vote/
          docker build -t ${{ secrets.DOCKER_USERNAME }}/worker:${{ github.sha }} worker/
          docker build -t ${{ secrets.DOCKER_USERNAME }}/result:${{ github.sha }} result/

      - name: Run tests - Vote (Java)
        working-directory: vote
        run: mvn test

      - name: Run tests - Worker (Go)
        working-directory: worker
        run: go test ./...

      - name: Run tests - Result (Node.js)
        working-directory: result
        run: npm install && npm test

      - name: Push images
        run: |
          docker push ${{ secrets.DOCKER_USERNAME }}/vote:${{ github.sha }}
          docker push ${{ secrets.DOCKER_USERNAME }}/worker:${{ github.sha }}
          docker push ${{ secrets.DOCKER_USERNAME }}/result:${{ github.sha }}

      - name: Deploy to Kubernetes
        run: |
          helm upgrade --install vote      infrastructure/vote      --set image.tag=${{ github.sha }}
          helm upgrade --install worker    infrastructure/worker    --set image.tag=${{ github.sha }}
          helm upgrade --install result    infrastructure/result    --set image.tag=${{ github.sha }}
```

---

## infra-pipeline.yml — Pipeline de infraestructura

### Responsabilidad

Provisionar y actualizar la infraestructura cloud (cluster Kubernetes, Kafka, PostgreSQL) usando Terraform. Se ejecuta cuando hay cambios en la rama de infraestructura o en los archivos de `/terraform`.

### Activación

```yaml
on:
  push:
    branches: [develop]
    paths:
      - 'terraform/**'
      - 'infrastructure/**'
  pull_request:
    branches: [staging, main]
    paths:
      - 'terraform/**'
      - 'infrastructure/**'
```

### Etapas

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Checkout    │───▶│  TF Init     │───▶│  TF Plan     │───▶│  TF Apply    │
│  del repo    │    │  (backend)   │    │  (preview)   │    │  (si es push)│
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### Descripción de cada etapa

**1. Checkout** — descarga el código del repositorio.

**2. Terraform Init** — inicializa el directorio de trabajo de Terraform y configura el backend remoto para almacenar el estado de la infraestructura.

**3. Terraform Plan** — genera y muestra un plan detallado de los cambios que se aplicarán a la infraestructura. En Pull Requests, este paso publica el plan como comentario en el PR para revisión del equipo de operaciones.

**4. Terraform Apply** — aplica los cambios al proveedor cloud. Solo se ejecuta en pushes directos (no en PRs), garantizando que los cambios hayan sido revisados y aprobados antes de aplicarse.

### Script de referencia

```yaml
name: Infra Pipeline

on:
  push:
    branches: [develop]
    paths:
      - 'terraform/**'
  pull_request:
    branches: [staging, main]
    paths:
      - 'terraform/**'

jobs:
  terraform:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Terraform Init
        working-directory: terraform/
        run: terraform init

      - name: Terraform Plan
        working-directory: terraform/
        run: terraform plan -out=tfplan

      - name: Terraform Apply
        if: github.event_name == 'push'
        working-directory: terraform/
        run: terraform apply -auto-approve tfplan
```

---

## Secrets requeridos

Configurar en **Settings → Secrets and variables → Actions** del repositorio:

| Secret | Descripción | Usado en |
|---|---|---|
| `DOCKER_USERNAME` | Usuario de Docker Hub | deploy-pipeline.yml |
| `DOCKER_PASSWORD` | Token de acceso de Docker Hub | deploy-pipeline.yml |
| `KUBECONFIG` | Configuración del cluster Kubernetes | deploy-pipeline.yml |
| `TF_API_TOKEN` | Token de Terraform Cloud (si aplica) | infra-pipeline.yml |

---


