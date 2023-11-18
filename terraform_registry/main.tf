terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  cloud_id  = "b1g0vh6uspd0m39d5er6"
  folder_id = "b1gqo3fhddgjd47bbisd"
  zone      = "ru-central1-a"
}

resource "yandex_container_registry" "docker-registry" {
  name = "docker-registry"
}

output "registry_id" {
  value = yandex_container_registry.docker-registry.id
}
