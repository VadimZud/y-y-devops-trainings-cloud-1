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

provider "yandex" {
  cloud_id  = "b1g0vh6uspd0m39d5er6"
  folder_id = var.folder_id
  zone      = "ru-central1-a"
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

resource "yandex_resourcemanager_folder_iam_member" "puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.catgpt_instance.id}"
}

resource "yandex_compute_instance" "catgpt" {
  name               = "catgpt"
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
    subnet_id = yandex_vpc_subnet.catgpt.id
    nat       = true
  }

  metadata = {
    docker-compose = templatefile("${path.module}/docker-compose.yaml.tftpl", { registry_id = data.yandex_container_registry.docker_registry.id })
    ssh-keys       = "ubuntu:${file("~/.ssh/devops_training.pub")}"
  }

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image_id]
  }
}

output "catgpt_ip" {
  value = yandex_compute_instance.catgpt.network_interface[0].nat_ip_address
}
