provider "google" {
  credentials = file("<PATH_TO_YOUR_SERVICE_ACCOUNT_KEY>.json")
  project     = "<YOUR_PROJECT_ID>"
  region      = "us-central1"
  zone        = "us-central1-a"
}

resource "google_compute_address" "new_static_ip" {
  name = "new-flask-app-static-ip"
}

resource "google_compute_instance" "new_flask_server" {
  tags = ["http-server"]
  name         = "new-flask-server"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.new_static_ip.address
    }
  }

  metadata = {
    MEILISEARCH_HOST     = var.meilisearch_host
    MEILISEARCH_API_KEY  = var.meilisearch_api_key
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash

    # Update and install packages
    apt-get update
    apt-get install -y python3 python3-pip git curl
    pip3 install flask gunicorn

    # Set env varibles
    export MEILISEARCH_MASTER_KEY="${MEILISEARCH_MASTER_KEY}"
    export MEILISEARCH_HOST="${MEILISEARCH_HOST}"

    # Setup and start meilisearch
    curl -L https://install.meilisearch.com | sh
    nohup ./meilisearch --master-key=$MEILISEARCH_MASTER_KEY &

    # Setup and start web server
    git clone https://github.com/vivalareda/notebook.sh.git
    cd notebook.sh
    pip install -r requirements.txt
    gunicorn --env -w 4 -b 0.0.0.0:5000 app:app


  EOF
}

resource "google_compute_firewall" "allow_http_new" {
  name    = "allow-http-traffic-new"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_dns_managed_zone" "new_dns_zone" {
  name        = "reda.sh"
  dns_name    = "reda.sh"
  description = "Managed DNS zone for the new Flask app"
}

resource "google_dns_record_set" "new_a_record" {
  name         = "reda.sh"
  managed_zone = google_dns_managed_zone.new_dns_zone.name
  type         = "A"
  ttl          = 300

  rrdatas = [
    google_compute_address.new_static_ip.address
  ]
}

variable "meilisearch_host" {}
variable "meilisearch_api_key" {}
