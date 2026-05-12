FROM grafana/tempo:2.10.5

COPY config/tempo.yml /etc/tempo.yml

ENTRYPOINT ["/tempo"]
CMD ["-config.file=/etc/tempo.yml", "-config.expand-env=true"]
