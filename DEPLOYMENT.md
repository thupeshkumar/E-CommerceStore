# E-CommerceStore: Docker + Terraform on AWS

This kit uses the actual React frontend and four Node.js services from https://github.com/thupeshkumar/E-CommerceStore. Run all numbered commands in **Ubuntu 22.04/24.04 Bash**, or **Ubuntu in WSL2** on Windows. Do not paste Bash commands into PowerShell. Start Docker Desktop with Linux containers and enable integration for your WSL Ubuntu distribution when using Windows.

## 1. Files and architecture

The supplied folder is a complete source snapshot with deployment additions. The original GitHub repository has not been changed. You can use this folder directly, or clone the repository and copy this kit over it:

```bash
git clone https://github.com/thupeshkumar/E-CommerceStore.git
cd E-CommerceStore
```

Use `DEPLOYMENT.md` as the deployment instructions; the original `README.md` describes development without containers.

```text
Browser -> EC2 public IP:80 -> frontend container (Nginx + React)
                                 /user/    -> user:3001
                                 /product/ -> product:3002
                                 /cart/    -> cart:3003
                                 /order/   -> order:3004
                                                   |
                                      mongo:27017 (private)
```

There are **five application images you build**, plus one official MongoDB supporting image. MongoDB is required by the real application. A custom VPC, public subnet, internet gateway, route table, security group, and one Ubuntu EC2 instance are created. The assignment requirement permits a custom VPC, despite the evaluation table mentioning a default VPC.

| Component | File / port |
|---|---|
| User Dockerfile | `backend/user-service/Dockerfile`, 3001 |
| Product Dockerfile | `backend/product-service/Dockerfile`, 3002 |
| Cart Dockerfile | `backend/cart-service/Dockerfile`, 3003 |
| Order Dockerfile | `backend/order-service/Dockerfile`, 3004 |
| Frontend Dockerfile | `frontend/Dockerfile`, 80 |
| Local build and run | `compose.yaml` |
| EC2 pull and run | `terraform/compose.yaml` |
| Infrastructure | `terraform/*.tf` |
| Docker installation and startup | `terraform/user-data.sh.tftpl` |

Only port 80 is published by Docker. Services communicate on the Compose network using service names. The security group also permits 3001–3004 from itself, satisfying internal port rules; those ports are not exposed publicly. Nginx prefixes are stripped before forwarding, so `/product/api/products` reaches `/api/products`. React uses relative API URLs rather than a visitor's `localhost`.

## 2. Prepare tools and accounts (before the timed exercise)

Install Git, Docker Engine with the Compose plugin (Linux), or Docker Desktop with WSL integration (Windows), Terraform >=1.6, and AWS CLI v2. See official installation instructions:

- Docker Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Docker Desktop Windows: https://docs.docker.com/desktop/setup/install/windows-install/
- Terraform: https://developer.hashicorp.com/terraform/install
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

On a fresh Ubuntu machine, install Git and curl with `sudo apt-get update && sudo apt-get install -y git curl openssl`. Install the other tools using the linked instructions. On Linux, use `sudo` for Docker commands if your account lacks Docker access, or configure the Docker group and sign out/in.

```bash
git --version
docker version
docker compose version
terraform version
aws --version
aws configure
aws sts get-caller-identity
```

Configure AWS credentials locally; never put access keys in Terraform files. Use an AWS identity permitted to manage EC2, VPC networking, security groups, volumes, and describe AMIs/availability zones. The region below is Mumbai (`ap-south-1`). EC2, EBS, and public IPv4 can incur charges; this guide does not assume free tier eligibility.

Create a Docker Hub account and five **public** repositories named `ecommerce-user`, `ecommerce-product`, `ecommerce-cart`, `ecommerce-order`, and `ecommerce-frontend`. This avoids storing registry credentials on EC2.

## 3. Configure local image names

From the project root:

```bash
cp .env.example .env
nano .env
```

Set your actual Docker Hub username, a tag such as `v1`, and a long random JWT secret. Generate the secret using `openssl rand -hex 32`, then paste it into `.env`:

```dotenv
DOCKERHUB_USERNAME=thupeshkumard
IMAGE_TAG=v1
JWT_SECRET=paste-your-generated-secret-here
```

Do not commit `.env`. EC2 generates a separate JWT secret locally during startup.

## 4. Build and test all five images manually (about 15–20 minutes)

```bash
docker login
docker compose config --quiet
# AWS instance is x86_64; build that architecture even on an ARM laptop.
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose build
docker compose up -d --wait --wait-timeout 300
docker compose ps
curl -fsS http://localhost/health
curl -fsS http://localhost/user/health
curl -fsS http://localhost/product/health
curl -fsS http://localhost/cart/health
curl -fsS http://localhost/order/health
curl -fsS http://localhost/user/
curl -fsS http://localhost/product/api/products
```

Open `http://localhost` in a browser. Expected: the React homepage; frontend health returns `Frontend is Live`; backend health returns JSON with service name and `status: OK`; `/user/` returns `user Service Running`. Products may initially be an empty list because there is no seed catalog.

The Dockerfiles start backend services with `node server.js`: the repository's `npm start` uses development-only nodemon. No local npm installation is required; dependencies are installed inside Docker. This source has no dependency lockfiles, so npm currently resolves the package ranges at image-build time. Preserve tested image tags; for stronger repeatability, generate and commit npm lockfiles and switch Dockerfiles to `npm ci` in a follow-up.

Test database-backed registration as well, since `/health` only checks the HTTP process:

```bash
curl -fsS -X POST http://localhost/user/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Demo","lastName":"Student","email":"demo@example.com","password":"DemoPassword123!"}'
```

Expected: a successful registration response with a token. Use a different email when repeating. This is a deployment exercise; it does not certify every existing shopping/payment workflow.

## 5. Push images to Docker Hub manually (about 5–10 minutes)

```bash
docker compose push
docker compose images
```

Compose builds and tags each image from its `image:` value, so a separate `docker tag` command is unnecessary. The resulting references are:

```text
youractualusername/ecommerce-user:v1
youractualusername/ecommerce-product:v1
youractualusername/ecommerce-cart:v1
youractualusername/ecommerce-order:v1
youractualusername/ecommerce-frontend:v1
```

Confirm all five tags appear in your public Docker Hub repositories before continuing. `mongo:7` is pulled directly from Docker Hub, and is not built or pushed by you. Terraform does not build images.

## 6. Create an EC2 key pair and configure Terraform (about 5 minutes)

In AWS Console > EC2 > Key pairs, select **Mumbai / ap-south-1**, create `ecommerce-key`, choose RSA and PEM, and save the downloaded key privately. The key pair name must exist in the same region as Terraform. Alternatively use an existing regional key pair.

```bash
curl -4 https://checkip.amazonaws.com
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Replace the username, key name, and example address. Use the public IPv4 printed above plus `/32`:

```hcl
aws_region         = "ap-south-1"
dockerhub_username = "youractualusername"
image_tag          = "v1"
instance_type      = "t3.small"
key_name           = "ecommerce-key"
admin_cidr         = "YOUR_PUBLIC_IPV4/32"
```

`t3.small` provides 2 GiB RAM for the six containers; using a micro instance can cause memory failures. Docker images are built locally, so EC2 does not need memory for the React build.

## 7. Provision and deploy (about 5–10 minutes)

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
terraform output
```

Outputs include `public_ip`, `public_dns`, `frontend_url`, and an SSH command template. Terraform completion means the EC2 instance exists; user-data continues independently. Allow several minutes for Docker installation and image pulls. Terraform does not wait for application readiness or fail automatically if user-data fails.

```bash
APP_URL=$(terraform output -raw frontend_url)
curl -fsS "$APP_URL/health"
```

Once this succeeds, open the printed URL in your browser, using **http://**, not HTTPS. No certificate or TLS listener is configured for this exercise.

## 8. Verify the AWS deployment (about 5 minutes)

```bash
curl -fsS "$APP_URL/user/health"
curl -fsS "$APP_URL/product/health"
curl -fsS "$APP_URL/cart/health"
curl -fsS "$APP_URL/order/health"
curl -fsS "$APP_URL/product/api/products"
```

Repeat the registration test from step 4 with `$APP_URL/user/api/auth/register` to verify MongoDB on EC2. To inspect containers, substitute the actual path to your downloaded PEM key:

```bash
chmod 400 /path/to/ecommerce-key.pem
PUBLIC_IP=$(terraform output -raw public_ip)
ssh -i /path/to/ecommerce-key.pem ubuntu@"$PUBLIC_IP"
sudo cloud-init status --wait
sudo tail -n 100 /var/log/ecommerce-bootstrap.log
sudo ls /opt/ecommerce/DEPLOYMENT_COMPLETE
cd /opt/ecommerce
sudo docker compose ps
sudo docker compose logs --tail=30 user product cart order frontend
sudo docker compose exec -T mongo mongosh --quiet --eval 'db.adminCommand("ping")'
```

Save screenshots of: Terraform outputs, the public homepage including its URL, container status, the four health responses, and Docker Hub's five image tags. Together with this guide and the Terraform files, these provide submission evidence.

## 9. Troubleshooting

| Symptom | Action |
|---|---|
| Local Docker permission or daemon error | Start Docker Desktop and WSL integration, or check the Linux Docker service and account access. |
| Port 80 already allocated locally | Stop the local service occupying port 80, then rerun Compose. |
| `pull access denied` on EC2 | Verify username/tag and public repository visibility. Read the bootstrap log. |
| Docker Hub pull rate limit | Wait for reset or use an account plan with sufficient allowance; this kit assumes anonymous public pulls on EC2. |
| Frontend unreachable immediately after apply | Wait for cloud-init, then inspect bootstrap log, route table, and port 80 security rule. |
| SSH timeout | Update `admin_cidr` to your current public IPv4/32 and apply; check the PEM and regional key name. |
| Backend health works but APIs fail | Inspect MongoDB health and service logs. HTTP health alone does not prove database connectivity. |
| React build fails or process is killed | Check the build output and allocate more Docker Desktop memory; install/build all frontend dev dependencies. |
| Terraform cannot find credentials | Run `aws sts get-caller-identity` in the same shell; configure AWS CLI or the correct AWS profile. |
| Empty products page | Database starts empty; use the existing product/category APIs to populate it if required. |

After fixing a transient image/network failure on EC2, run `cd /opt/ecommerce && sudo docker compose pull && sudo docker compose up -d --wait --wait-timeout 300`. If Docker installation itself failed, inspect `/var/log/cloud-init-output.log`, fix the cause, then rerun the script with `sudo bash /var/lib/cloud/instance/scripts/part-001`.

## 10. Updates, persistence, and cleanup

For a new release, set a **new** `IMAGE_TAG` in root `.env`, build, test, and push again. Update `image_tag` in `terraform.tfvars`, review a new plan, and apply. Changing user-data replaces the EC2 instance in this kit; the old MongoDB volume is on its root EBS disk and is lost on replacement or destroy. The generated EC2 JWT secret also changes. Back up data before replacement if you need it. This is a single-instance classroom deployment with HTTP, no database authentication, no high availability, and existing application authorization limitations; use only demo data.

Stop local containers when done (from project root):

```bash
docker compose down
# Add --volumes only if you intentionally want to delete the LOCAL database.
```

Delete AWS resources after evaluation (from `terraform/`):

```bash
terraform destroy
```

Review and confirm the destruction plan. Keep Terraform state until cleanup is complete. State, credentials, `.env`, private keys, and saved plans must not be published. The manually created EC2 key pair and Docker Hub repositories remain after destroy.

## Suggested one-hour allocation

| Task | Minutes |
|---|---:|
| Confirm tools, source, and variables | 5 |
| Build and test five application images | 20 |
| Push five public images | 10 |
| Terraform plan/apply and bootstrap | 15 |
| Verify and capture documentation evidence | 10 |

Network speed and first-time dependency downloads can extend this. Prepare tool installation and AWS/Docker Hub account access beforehand.

## Validation of this deliverable

See `VALIDATION.md` for checks actually performed. No AWS deployment or Docker Hub push has been performed on your behalf.
