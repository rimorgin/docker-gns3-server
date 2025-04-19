FROM alpine:latest

# Copy files into the container
ADD ./start.sh /start.sh
ADD ./postinstall.sh /postinstall.sh
ADD ./config.ini /config.ini
ADD ./requirements.txt /requirements.txt
COPY dependencies.json /tmp/dependencies.json

# Convert potential CRLF to LF and make scripts executable
RUN sed -i 's/\r$//' /start.sh /postinstall.sh && \
    chmod +x /start.sh /postinstall.sh

# Install dependencies and Python requirements
RUN mkdir /data && \
    apk add --no-cache --virtual=build-dependencies jq gcc python3-dev musl-dev linux-headers && \
    jq -r 'to_entries | .[] | .key + "=" + .value' /tmp/dependencies.json | xargs apk add --no-cache && \
    pip install -r /requirements.txt --break-system-packages && \
    apk del --purge build-dependencies

# Workaround for GNS3 bug
RUN ln -s /bin/busybox /usr/lib/python*/site-packages/gns3server/compute/docker/resources/bin || true

WORKDIR /data

VOLUME ["/data"]

CMD [ "/start.sh" ]
