#!/usr/bin/env python3

from pprint import pprint
import argparse
import sys
import json
import logging

from pymongo import MongoClient
from bson import json_util
from decouple import config
from covis_db import db, hosts

from covis_worker import rezip


parser = argparse.ArgumentParser()

parser.add_argument('--dbhost', default=config('MONGODB_URL',
                    default="mongodb://localhost/"),
                    help='URL (mongodb://hostname/) of MongoDB host')

parser.add_argument('--dest-host', dest="desthost", default="COVIS-NAS",
                    help='Destination host')

parser.add_argument('--log', metavar='log', nargs='?',
                    default=config('LOG_LEVEL', default='INFO'),
                    help='Logging level')

parser.add_argument('--count', default=0, type=int,
                    metavar='N',
                    help="Only queue N entries (used for debugging)")

parser.add_argument('--dry-run', dest='dryrun', action='store_true')

parser.add_argument('--run-local', dest='runlocal', action='store_true')

parser.add_argument('--skip-dmas', dest='skipdmas', action='store_true',
                    help='Skip files which are only on DMAS')

args = parser.parse_args()
logging.basicConfig( level=args.log.upper() )

# Validate destination hostname
if not hosts.validate_host(args.desthost):
    print("Can't understand destination host \"%s\"" % args.desthost)
    exit()

client = db.CovisDB(MongoClient(args.dbhost))

selector = [
    {"$match": { "$and":
                [ { "raw.host": { "$not": { "$eq": "COVIS-NAS" } } } ]
    } }
]

## Should be able to implement skipdmas as a MongoDB selector
# if args.skipdmas:
#     selector[0]["$match"]["$and"].append( { "raw.host": { "$not": { "$eq": "DMAS" } } } )

if args.count > 0:
    selector.append( {"$sample": {"size": args.count} } )

# Find run which are _not_ on NAS
result = client.runs.aggregate( selector )


for elem in result:

    run = db.CovisRun(elem)

    logging.info("Considering basename %s" % (run.basename))

    locations = [raw.host for raw in run.raw]

    if args.skipdmas and locations == ["DMAS"]:
        logging.info("    File only on DMAS, skipping...")
        continue


    logging.info("Queuing rezip job for %s on %s" % (run.basename, ','.join(locations)))

    if args.dryrun:
        print("Dry run, skipping...")
        continue

    if args.runlocal:
        job = rezip.rezip(run.basename,args.desthost)
    else:
        job = rezip.rezip.delay(run.basename,args.desthost)
