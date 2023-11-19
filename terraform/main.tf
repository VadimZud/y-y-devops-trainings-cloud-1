terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

variable "folder_id" {
  type    = string
  default = "b1gqo3fhddgjd47bbisd"
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

provider "yandex" {
  cloud_id  = "b1g0vh6uspd0m39d5er6"
  folder_id = var.folder_id
  zone      = var.zone
}

data "yandex_container_registry" "docker_registry" {
  name = "docker-registry"
}

data "yandex_compute_image" "container_optimized_image" {
  family = "container-optimized-image"
}

resource "yandex_vpc_network" "catgpt" {
  name = "catgpt"
}

resource "yandex_vpc_subnet" "catgpt" {
  network_id     = yandex_vpc_network.catgpt.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_iam_service_account" "catgpt_instance" {
  name = "zudvadim-catgpt-instance"
}

resource "yandex_resourcemanager_folder_iam_member" "catgpt_instance_roles" {
  for_each = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  folder_id = var.folder_id
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.catgpt_instance.id}"
}

resource "yandex_iam_service_account" "catgpt_instance_group" {
  name = "zudvadim-catgpt-instance-group"
}

resource "yandex_resourcemanager_folder_iam_member" "catgpt_instance_group_roles" {
  for_each = toset([
    "compute.editor",
    "vpc.admin",
    "iam.serviceAccounts.admin",
    "load-balancer.admin",
  ])
  folder_id = var.folder_id
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.catgpt_instance_group.id}"
}

resource "yandex_compute_instance_group" "catgpt" {
  name               = "catgpt"
  service_account_id = yandex_iam_service_account.catgpt_instance_group.id

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

  allocation_policy {
    zones = [var.zone]
  }

  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.catgpt_instance.id

    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }

    scheduling_policy {
      preemptible = true
    }

    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.container_optimized_image.id
      }
    }

    network_interface {
      network_id = yandex_vpc_network.catgpt.id
      subnet_ids = [yandex_vpc_subnet.catgpt.id]
      nat        = true
    }

    metadata = {
      docker-compose = templatefile("${path.module}/docker-compose.yaml.tftpl", {
        registry_id = data.yandex_container_registry.docker_registry.id
        folder_id   = var.folder_id
      })
      ssh-keys = "ubuntu:${file("~/.ssh/devops_training.pub")}"
      user-data = templatefile("${path.module}/cloud_config.yaml.tftpl", {
        unified_agent_config = base64encode(templatefile("${path.module}/unified_agent.yml.tftpl", {
          folder_id = var.folder_id
        }))
      })
    }
  }

  load_balancer {}

  depends_on = [
    yandex_resourcemanager_folder_iam_member.catgpt_instance_roles,
    yandex_resourcemanager_folder_iam_member.catgpt_instance_group_roles,
  ]

  lifecycle {
    ignore_changes = [instance_template[0].boot_disk[0].initialize_params[0].image_id]
  }
}

resource "yandex_lb_network_load_balancer" "load_balancer" {
  name = "catgpt-load-balancer"

  listener {
    name = "my-listener"
    port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.catgpt.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}
