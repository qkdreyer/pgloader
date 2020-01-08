#!/bin/bash

# MSSQL_SERVER_ADDR/PSQL_SERVER_ADDR can be either IP Address or FQDN.
# When running inside a docker network with SQL Server and PSQL containers
# you can leverage their hostname or kube svc address.

# The --network is variable, byo..


docker run -it \
-e MSSQL_USER=sa \
-e MSSQL_PASS=VerySecure123 \
-e MSSQL_SERVER_ADDR=sqlserver \
-e SOURCE_DB=confluence \
-e PSQL_USER=confluence \
-e PSQL_PASS=confluence \
-e PSQL_SERVER_ADDR=psql \
-e DEST_DB=confluence \
--network=atlassian \
mbern/pgloader-confluence:latest