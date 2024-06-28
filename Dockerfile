FROM prom/prometheus:v2.37.9

# Set the working directory to /etc/prometheus
WORKDIR /etc/prometheus

# Copy the prometheus.yml file from the host into the container at /etc/prometheus/
COPY prometheus.yaml /etc/prometheus/

# Expose the Prometheus web UI and API ports
EXPOSE 9090

# Start Prometheus with the configuration file
CMD ["--config.file=/etc/prometheus/prometheus.yaml"]