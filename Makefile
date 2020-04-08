
## Docker-related tasks
TEST_TAG=amarburg/covis-worker:test
PROD_TAG=amarburg/covis-worker:prod

default: help

help:
	@echo "make docker        Build test covis-worker docker image \"${TEST_TAG}\""
	@echo "make force_docker  Build test covis-worker docker image \"${TEST_TAG}\" with --no-cache"
	@echo "make push          Push test covis-worker docker image \"${TEST_TAG}\""
	@echo "make prod          Label current test as \"prod\" and push to \"${PROD_TAG}\""

# == Tasks related to building __test__ image =======================
#
docker: covis_worker/static_git_info.py
	docker build -t ${TEST_TAG} .

force_docker: covis_worker/static_git_info.py
	docker build --no-cache -t ${TEST_TAG} .

push: build
	docker push ${TEST_TAG}

## Jobs related to building __prod__ image
prod: build
	docker tag ${TEST_TAG} ${PROD_TAG}
	docker push ${PROD_TAG}


# == Tasks related to testing locally (not in Docker) ===============
# Run pytest
local_pytest:
	pytest

# == Tasks related to testing in the Docker image ====================
#
pytest: check_test_docker
	pytest

# == Test for existence of required docker services =================

TESTDATA_DIR=test_stack

run_test_stack: check_test_data
	cd ${TESTDATA_DIR} && docker-compose up

check_test_stack: check_test_data check_test_stack_ssh_keys
	if ! docker ps --quiet --filter name=covistestdata --format "{{.Names}}" | grep "covistestdata" ; then \
		echo "Test docker network not running.  \"make run_test_docker\" or \"cd testdata && docker-compose up\""; \
	fi

check_test_data:
	@if [ ! -f ${TESTDATA_DIR}/covis-nas/covis-raw/2019/10/24/COVIS-20191024T000002-imaging1.7z ]; then \
		echo \"${TESTDATA_DIR}/\" not populated, please \"cd ${TESTDATA_DIR} && make download\"; \
  fi

## Generate SSH keys for test SFTP server in Docker-Compose and pytest
check_test_stack_ssh_keys: tmp/ssh_keys/id_rsa.pub

tmp/ssh_keys/id_rsa.pub:
	mkdir -p tmp/ssh_keys/
	ssh-keygen -t ed25519 -f tmp/ssh_keys/ssh_host_ed25519_key < /dev/null
	ssh-keygen -t rsa -b 4096 -f tmp/ssh_keys/ssh_host_rsa_key < /dev/null
	ssh-keygen -t rsa -b 4096 -f tmp/ssh_keys/id_rsa < /dev/null

# == Tasks for bootstrapping the database in the test network ==

DOCKER_NETWORK=${TESTDATA_DIR}_covistest

## Load test data into the MongoDB test database
import_test_data:
	cat seed_data/seed_data.json | docker exec -i \
 						$$(docker-compose --file ${TESTDATA_DIR}/docker-compose.yml ps -q mongodb)  \
 						mongoimport --verbose --host mongodb:27017 \
						 						--db covis --collection runs --drop --jsonArray

dump_test_stack:
	docker exec -i \
 						$$(docker-compose --file ${TESTDATA_DIR}/docker-compose.yml ps -q mongodb)  \
 						mongoexport --host mongodb:27017 \
						--db covis --collection runs

# == Tasks related to extracting Git metadata ==
#
GITREV=${shell git rev-parse HEAD }
GITTAG=${shell git describe --tags }
GITDIRTY_proc=${shell git status --porcelain --untracked-files=no }
ifeq ($(.SHELLSTATUS),0)
  GITDIRTY = "False"
else
	GITDIRTY = "True"
endif

covis_worker/static_git_info.py:
	echo "def add_static_git_info( d ):\n" > $@
	printf "   d[\"covis_worker_gitrev\"] = '%s'\n" ${GITREV} >> $@
	printf "   d[\"covis_worker_gittags\"] = '%s'\n" ${GITTAG} >> $@
	printf "   d[\"covis_worker_git_dirty\"] = %s\n" ${GITDIRTY} >> $@


.PHONY: help \
	 			docker force_docker push \
				import_seed_data \
				check_test_data check_test_docker check_test_stack_ssh_keys run_test_stack \
				local_pytest

# == Old / less organized tasks =============================================

# -V drops anonymous volumes so mongodb data isn't persisted
# up:
# 	docker-compose -p covis up  -V

## The services in docker_compose.yml must exist for testing
drop_test_db:
	mongo covis --eval 'db.runs.drop()'



## Builds the small db
${TEST_DATA}/test_db.bson: ${TEST_DATA}/old_covis_nas1.txt ${TEST_DATA}/covis_dmas.json
	mongo covis --eval 'db.runs.drop()'
	apps/import_file_list.py --covis-nas old-covis-nas1 --log INFO ${TEST_DATA}/old_covis_nas1.txt
	apps/import_file_list.py --dmas --log INFO ${TEST_DATA}/covis_dmas.json
	mongodump -d covis -c runs -o - > $@

reset_test_db: ${TEST_DATA}/test_db.bson
	mongorestore -d covis -c runs --drop --dir=- < $<



## Run sample jobs against local test_up netestdata_and_compose_covistesttwork
DOCKER_NETWORK= testdata_covistest

CLIENT_ENV = -e RAW_S3_HOST=covistestdata:9000 \
							-e RAW_S3_ACCESS_KEY=covistestdata \
							-e RAW_S3_SECRET_KEY=covistestdata \
							-e OUTPUT_S3_HOST=covistestdata:9000 \
							-e OUTPUT_S3_ACCESS_KEY=covistestdata \
							-e OUTPUT_S3_SECRET_KEY=covistestdata

DOCKER_RUN=docker run --rm -it --network ${DOCKER_NETWORK} ${CLIENT_ENV}
DOCKER_RUN_TEST=${DOCKER_RUN} ${TEST_TAG}

# Attach a test worker to the covis_Default test network ... for use with non-"local"
# jobs below
test_worker:
	${DOCKER_RUN_TEST}

postprocess_diffuse3.7z_local:
	${DOCKER_RUN_TEST} apps/queue_postprocess.py --log DEBUG \
					--run-local s3://covis-raw/2019/10/24/COVIS-20191024T003346-diffuse3.7z \
					--output    s3://covis-postprocessed/2019/10/24/COVIS-20191024T003346-diffuse3

postprocess_diffuse3.7z_worker:
	${DOCKER_RUN_TEST} apps/queue_postprocess.py  --log DEBUG \
					s3://covis-raw/2019/10/24/COVIS-20191024T003346-diffuse3.7z \
					--output    s3://covis-postprocessed/2019/10/24/COVIS-20191024T003346-diffuse3

postprocess_local_job:
	${DOCKER_RUN_TEST} apps/queue_postprocess.py --log DEBUG --job test-job --run-local APLUWCOVISMBSONAR001_20111001T210757.973Z-IMAGING

postprocess_job: build
	${DOCKER_RUN_TEST} apps/queue_postprocess.py --log INFO --job test-job  APLUWCOVISMBSONAR001_20111001T210757.973Z-IMAGING

## Use test docker image to import (and potentially rezip) files
## from the test SFTP site
test_sftp_import: build reset_test_db test_ssh_keys
	${DOCKER_RUN} -v $(CURDIR)/tmp/ssh_keys/:/tmp/sshkeys:ro ${TEST_TAG} \
						apps/import_sftp.py  --run-local --log INFO --privkey /tmp/sshkeys/id_rsa --force sftp://sftp:22/

test_rezip_local: build reset_test_db
	${DOCKER_RUN} -v $(CURDIR)/tmp/ssh_keys/:/tmp/sshkeys:ro ${TEST_TAG} \
					 apps/queue_rezip.py  --run-local --log INFO --skip-dmas

test_validate_db: build
	${DOCKER_RUN_TEST} apps/validate_db.py --log INFO --dry-run

test_validate_minio: build
	${DOCKER_RUN_TEST} apps/validate_minio.py --log INFO --dry-run covis-nas



## How to scrape db
## apps/run_metadata_report.py   --dbhost "mongodb://user:passwd@hostname:27017/covisprod?authSource=covisprod" | tee ${FILENAME}.csv
##





## Sftp into the sftp test server created by docker-compose.yml
sftp:
	sftp -P 2222 -i tmp/ssh_keys/id_rsa covis@localhost

.PHONY: test_ssh_keys


## Builds the large db
# bootstrap_large_db: test/data/covis_dmas.json
# 	mongo covis --eval 'db.runs.drop()'
# 	apps/import_file_list.py --dmas --log INFO  test/data/covis_dmas.json
# 	apps/import_file_list.py --covis-nas old-covis-nas1 --log INFO  test/data/old_covis_nas1.txt
# 	apps/import_file_list.py --covis-nas old-covis-nas6 --log INFO  test/data/old_covis_nas6.txt
# 	mongodump -d covis -c runs -o - > test/data/large_db_dump.bson
#
# reset_large_db: test/data/large_db_dump.bson
# 	mongorestore -d covis -c runs --drop --dir=- < $^

.PHONY: test test_up drop_test_db reset_test_db



#  Retrieve list of 2010-2015 COVIS files currently on ONC DMAS
#  Saves results to seed_data/
scrape_dmas:
	curl -o seed_data/covis_dmas_2010_2012.json \
					"http://dmas.uvic.ca/api/archivefiles?method=getList&token=$(DMAS_TOKEN)&station=KEMF&deviceCategory=COVIS&dateFrom=2010-01-01T00:00:00.000Z&dateTo=2013-01-01T00:00:00.000Z"
	curl -o seed_data/covis_dmas_2013.json \
					"http://dmas.uvic.ca/api/archivefiles?method=getList&token=$(DMAS_TOKEN)&station=KEMF&deviceCategory=COVIS&dateFrom=2013-01-01T00:00:00.000Z&dateTo=2014-01-01T00:00:00.000Z"
	curl -o seed_data/covis_dmas_2014.json \
					"http://dmas.uvic.ca/api/archivefiles?method=getList&token=$(DMAS_TOKEN)&station=KEMF&deviceCategory=COVIS&dateFrom=2014-01-01T00:00:00.000Z&dateTo=2015-01-01T00:00:00.000Z"
	curl -o seed_data/covis_dmas_2015.json \
					"http://dmas.uvic.ca/api/archivefiles?method=getList&token=$(DMAS_TOKEN)&station=KEMF&deviceCategory=COVIS&dateFrom=2015-01-01T00:00:00.000Z&dateTo=2018-01-01T00:00:00.000Z"

#  Import DMAS and local NAS seed_data to a MongoDB instance
import_dmas: seed_data/covis_dmas_*.json
	apps/import_file_list.py --dmas --log INFO  seed_data/covis_dmas_2010_2012.json
	apps/import_file_list.py --dmas --log INFO  seed_data/covis_dmas_2013.json
	apps/import_file_list.py --dmas --log INFO  seed_data/covis_dmas_2014.json
	apps/import_file_list.py --dmas --log INFO  seed_data/covis_dmas_2015.json


COVIS_NAS = 1 3 5 6
import_covis_nas: seed_data/covis-nas?.txt
	$(foreach var,$(COVIS_NAS),apps/import_file_list.py --log INFO --covis-nas old-covis-nas$(var) seed_data/covis-nas$(var).txt;)

seed_data/seed_data.bson: drop_db import_dmas import_covis_nas
	mongodump -d covis -o - > seed_data/seed_data.bson
#
# import_seed_data: seed_data.bson
# 		mongorestore -d covis -c runs --drop --dir=- < seed_data/seed_data.bson


# Dump mongodb to a JSON test file
dump_json:
	apps/dump_mongo.py > dump.json

dump:
	apps/dump_mongo.py

backup:
	mongodump -o mongodb.backup --gzip

restore:
	mongorestore mongodb.backup

## Assumes ENV variable MONGODB_URL
##   Note the MONGODB_URL from Rancher will not work ... need to manually set
##   the server address to a local IP rather than the rancher service name "mongodb"
backup_prod:
	mongodump -vvvv --uri "${MONGODB_URL}" --out backup_prod --gzip

## Assumes a local mongodb is running
##   docker run -p 27017:27017 bitnami/mongodb:3.6
bootstrap_local:
	mongorestore -v --gzip --drop backup_prod
