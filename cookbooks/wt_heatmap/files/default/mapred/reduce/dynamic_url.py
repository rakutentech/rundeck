#!/usr/bin/env python

# USAGE:
#   dynamic_url.py
#
# INPUT:
#   json, ds, hr
#
# INPUT ORDERING:
#   none
#
# OUTPUT:
#   json
#
# WORKFLOW:
#   1. accept 3 fields (json string, date string, hour string)
#   2. merge into single json object
#   3. determine page_key, append to json object
#   4. emit json object
#
# DESCRIPTION:
#   Simple decorator pattern. This scripts accepts json logs out of hive
#   with a date and hour partition. It determines the "dynamic url" of the
#   event, appeds the value and emits for any downstream source.

import sys
import hashlib
import httplib

try: import simplejson as json
except ImportError: import json

# functions #####################################################################

account_ids = {}


# functions #####################################################################

def sha1(str):
	h = hashlib.sha1()
	h.update(str)
	return h.hexdigest()


# body ##########################################################################

conn = httplib.HTTPConnection("vcd01.staging.dmz:8097")
conn.request("GET", "/Config/dcsid2account")
response = conn.getresponse()
if response.status != 200:
	sys.stderr.write("Bad http request status: %i %s\n" % (response.status, response.reason))
	exit(-1)

try:
	account_ids = json.loads(response.read())
except Exception, e:
	sys.stderr.write("Unable to parse json from http result\n")
	raise

while True:
	try:
		line = sys.stdin.readline()
		if not line:
			break

		# get parameters (workflow #1)
		params = dict(zip(["json","ds","hr"],line.rstrip("\n").split("\t")))
		obj = json.loads(params["json"])

		# convert WT.blah params to WT_blah
		obj = dict((k.replace('.','_'), obj[k]) for k in obj)
		
		# only continue if we know the account-id for the dcs-id
		if not(obj["dcs-id"] in account_ids):
			continue
			
		# makes it easy to watch these fields (workflow #2)
		obj["ds"] = params["ds"]
		obj["hr"] = params["hr"]

		# determine page hash (workflow #3)
		page_ident = obj["cs-uri-stem"]
		if "WT_hm_url" in obj:
			page_ident += "?" + obj["WT_hm_url"]

		obj["page_ident"] = page_ident
		obj["account-id"] = account_ids[obj["dcs-id"]]
		obj["page_key"] = str(obj["account-id"]) + ";" + obj["cs-host"] + ";" + sha1(page_ident)
		
		# emit (workflow #4)
		sys.stdout.write("%s\n" % (json.dumps(obj)))

	except Exception, e:
		sys.stderr.write("error: %s on line %s\n" % (e, line))

