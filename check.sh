#!/usr/bin/env bash

echo -n "checking ... "

shellcheck --shell=bash --exclude=1003,1090,1117,2012,2016,2018,2019,2021,2086,2119,2120,2155,2181,2206,2207 ./shared/runlast.sh && echo 'passed!' || echo 'failed!'
