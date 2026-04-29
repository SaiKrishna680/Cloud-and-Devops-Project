# ─────────────────────────────────────────────────────────────────────────────
# terraform/modules/vpc/main.tf
#
# CREATES:
#   - 1 VPC
#   - 2 Public subnets  (Jenkins, SonarQube, Nexus — have public IPs)
#   - 2 Private subnets (EKS worker nodes — no direct internet access)
#   - Internet Gateway  (public subnet internet access)
#   - NAT Gateway       (private subnet outbound access)
#   - Route Tables
#
# WHY PUBLIC FOR TOOLS:
#   Jenkins, SonarQube, Nexus need to be accessible from your browser.
#   In production, put them behind an ALB with restricted access.
#
# WHY PRIVATE FOR EKS NODES:
#   Worker nodes should not be directly reachable from the internet.
#   Traffic flows: Internet → ALB → EKS Service → Pod
# ─────────────────────────────────────────────────────────────────────────────

# ── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # Required for EKS
  enable_dns_support   = true # Required for EKS

  tags = {
    Name = "${var.project_name}-vpc"
    # EKS requires these tags on the VPC
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # EC2 instances get public IPs

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    # EKS tag for external load balancers
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    # EKS tag for internal load balancers
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# ── NAT Gateway (in first public subnet) ──────────────────────────────────────
# WHY: EKS nodes in private subnets need outbound internet (pull images, AWS APIs)
# NOTE: NAT Gateway costs ~$0.045/hr + data transfer. Delete when not in use.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}

# ── Public Route Table ────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ── Associate public subnets with public route table ──────────────────────────
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ── Associate private subnets with private route table ────────────────────────
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Data source for AZs ────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}
