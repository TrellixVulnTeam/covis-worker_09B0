#!/usr/bin/env python3

# Dumps the mongodb to JSON .... this is strictly for debugging purposes,
# as some data may be lost in translation to human-readable formatself.
# Use mongodump or backup_mongo (which is a thin wrapper around mongodump) to make backups.

from pprint import pprint
import argparse
import sys
import json

from pymongo import MongoClient
from bson import json_util
from decouple import config
from covis_db import db


parser = argparse.ArgumentParser()

parser.add_argument('--dbhost', default=config('MONGODB_URL', default="mongodb://localhost/"),
                    help='URL (mongodb://hostname/) of MongoDB host')

args = parser.parse_args()

client = db.CovisDB( MongoClient(args.dbhost ) )
cursor = client.runs.find().sort('datetime')

print("[")
for elem in cursor:
    # print(json.dumps(json.loads(json_util.dumps(elem,indent=2))))
    print(json_util.dumps(elem,indent=2))
    if cursor.alive:
        print(',')

print("]")



#print("%d elements in total" % cursor.count(), file=sys.stderr)
