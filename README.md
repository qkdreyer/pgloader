# PGLoader-Confluence

This is a fork of [pgloader](https://github.com/dimitri/pgloader) based on the last stable v.3.6.1 release. 

This fork has a modified Dockerfile which is pre-baked to for MSSQL to Postgres migrations.

## Why a fork?
I needed a repeatable environement, but needed to resolve a few bugs present in master, and other fixed in mixed and matched versions of PGLoader. 

This fork includes SSL fixes for several issues and bugs when connecting to SQL Server instances. Key items to note at runtime;
* Includes a freetds.conf with UTF8 encoding
* Includes OpenSSL/LibSSL
* Has a templated sample DSL

## Running this image:
This image accepts several environment varaibles when run. These must be set.

## Quick Start:
`docker run -e MSSQL_USER=sa -e MSSQL_PASS=averysecurepassword -e "MSSQL_SERVER_ADDR=192.168.10.3" -e SOURCE_DB=confluence -e PSQL_USER=confluence -e PSQL_PASS=confluence -e "PSQL_SERVER_ADDR=192.168.10.3" -e DEST_DB=confluence mbern/pgloader-confluence:latest`

### Envs

* `MSSQL_USER` ( same user as confluence application )

* `MSSQL_PASS` ( the obvious )

* `MSSQL_SERVER_ADDR` ( ip/fqdn/hostname of SQL Server )

* `SOURCE_DB` ( the source database )

* `PSQL_USER` ( the target user in postgres )

* `PSQL_USER` ( .. )

* `PSQL_SERVER_ADDR` ( ip/fqdn/hostname of Postgres Server )

* `DEST_DB` ( the destination database in postgres )

## Customizing the DSL
Modify and create your DSL in the ```migration_playbook``` file. Standard Syntax and clauses/statements are documeted at PGLoader. 

## Running inside a docker network
This is designed to be run within a docker based network such as overlay or Kubernetes. Simply change the ```MSSQL_SERVER_ADDR``` and ```PSQL_SERVER_ADDR``` to the hostname of the source/targets and run within the same network. Two samples shown below;

### Docker Network Quick Start:
`docker run -e MSSQL_USER=sa -e MSSQL_PASS=averysecurepassword -e "MSSQL_SERVER_ADDR=192.168.10.3" -e SOURCE_DB=confluence -e PSQL_USER=confluence -e PSQL_PASS=confluence -e "PSQL_SERVER_ADDR=192.168.10.3" -e DEST_DB=confluence --network=atlassian mbern/pgloader-confluence:latest`

### Kubernetes Network Quick Start:
Create a v1/pod and reference the SVC of postgres or external CloudSQL connections
`docker run -e MSSQL_USER=sa -e MSSQL_PASS=averysecurepassword -e "MSSQL_SERVER_ADDR=sqlserver.atlassian-dev-ns" -e SOURCE_DB=confluence -e PSQL_USER=confluence -e PSQL_PASS=confluence -e "PSQL_SERVER_ADDR=postgres.atlassian-dev-ns" -e DEST_DB=confluence mbern/pgloader-confluence:latest`

## Other images to test with:
Pre-baked postgres image with several databased for development: https://hub.docker.com/repository/docker/mbern/postgres-atlas-all
Atlassian Confluence: https://hub.docker.com/r/atlassian/confluence-server/
