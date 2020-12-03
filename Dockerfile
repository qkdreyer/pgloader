FROM debian:bullseye-slim as builder

  RUN apt-get update \
      && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        curl \
        freetds-dev \
        gawk \
        git \
        libsqlite3-dev \
        libssl1.1 \
        libzip-dev \
        make \
        openssl \
        patch \
        sbcl \
        time \
        unzip \
        wget \
        cl-ironclad \
        cl-babel \
      && rm -rf /var/lib/apt/lists/*

  COPY ./ /opt/src/pgloader

  RUN mkdir -p /opt/src/pgloader/build/bin \
      && cd /opt/src/pgloader \
      && make

FROM debian:stable-slim

  RUN apt-get update \
      && apt-get install -y --no-install-recommends \
        curl \
        freetds-dev \
        gawk \
        libsqlite3-dev \
        libzip-dev \
        make \
        sbcl \
        unzip \
      && rm -rf /var/lib/apt/lists/*

  COPY --from=builder /opt/src/pgloader/build/bin/pgloader /usr/local/bin
  ADD migration_playbook /usr/local/bin
  ADD freetds.conf /etc/freetds/freetds.conf

  ENV MSSQL_USER=
  ENV MSSQL_PASS=
  ENV MSSQL_SERVER_ADDR=
  ENV SOURCE_DB=

  ENV PSQL_USER=
  ENV PSQL_PASS=
  ENV PSQL_SERVER_ADDR=
  ENV PSQL_PORT=5432
  ENV DEST_DB=

  CMD /usr/local/bin/pgloader -v --debug --on-error-stop /usr/local/bin/migration_playbook

  LABEL maintainer="Dimitri Fontaine <dim@tapoueh.org>"
