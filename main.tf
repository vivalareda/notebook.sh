variable "meilisearch_host" {}
variable "meilisearch_api_key" {}
variable "google_credentials" {}
variable "google_project" {}

provider "google" {
  credentials = file(var.google_credentials)
  project     = var.google_project
  region      = "us-central1"
  zone        = "us-central1-a"
}

resource "google_compute_address" "new_static_ip" {
  name = "new-flask-app-static-ip"
}

resource "google_compute_instance" "new_flask_server" {
  name         = "new-flask-server"
  machine_type = "e2-micro"
  zone         = "us-central1-a"
  tags         = ["http-server"]

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
    MEILISEARCH_HOST       = var.meilisearch_host
    MEILISEARCH_MASTER_KEY = var.meilisearch_api_key
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -x

    # Install packages
    echo "[$(date)] Starting package installation..." >> /var/log/startup-script.log
    sudo apt-get update && sudo apt-get install -y python3 python3-pip git curl
    echo "[$(date)] Finished package installation..." >> /var/log/startup-script.log

    # Fetch metadata
    MEILISEARCH_MASTER_KEY=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/MEILISEARCH_MASTER_KEY || echo "missing")
    MEILISEARCH_HOST=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/MEILISEARCH_HOST || echo "missing")

    # Set env variables globally
    export MEILISEARCH_MASTER_KEY="$MEILISEARCH_MASTER_KEY"

    # Setup and start Meilisearch
    curl -L https://install.meilisearch.com | sh
    sudo nohup ./meilisearch --master-key=$MEILISEARCH_MASTER_KEY > /var/log/meilisearch.log 2>&1 &

    # Create directory and clone
    mkdir /home/flaskapp/
    git clone https://github.com/vivalareda/notebook.sh.git /home/flaskapp/notebook.sh

    # Install dependencies and start server
    cd /home/flaskapp/notebook.sh
    pip install -r requirements.txt
    sudo MEILISEARCH_MASTER_KEY=$MEILISEARCH_MASTER_KEY gunicorn -w 4 -b 0.0.0.0:80 app:app --log-file /var/log/gunicorn.log &

  EOF
}

resource "google_compute_firewall" "allow_http_traffic" {
  name    = "allow-http-traffic"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

output "instance_name" {
  value = google_compute_instance.new_flask_server.name
}

output "static_ip" {
  value = google_compute_address.new_static_ip.address
}
