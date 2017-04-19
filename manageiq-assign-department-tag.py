#!/usr/bin/python
"""
Add / Delete a department tag in ManageIQ
"""

import json
import sys
import simplejson as json
import argparse
import socket
try:
    import requests
    from requests.packages.urllib3.exceptions import InsecureRequestWarning
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
except ImportError:
    print "Please install the python-requests module."
    sys.exit(-1)

# URL to ManageIQ server
URL = 'https://<MIQSERVERFQDN>'

# URL for the API to your deployed Satellite 6 server
# global MIQ_API, MIQ_API_URL
# global auth, current_token
MIQ_API = "%s/api/" % URL
hostName = socket.gethostname()

# Katello-specific API
POST_HEADERS = {'Content-Type': 'application/json'}

# Ignore SSL for now
SSL_VERIFY = False

def spinning_cursor():
    """
    You spin me right round baby right round
    """
    while True:
        for cursor in '|/-\\':
            yield cursor

spinner = spinning_cursor()

def get_json(location, params=None):
    """
    Performs a GET using the passed URL location
    """
    result = requests.get(
        location,
        params=params,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=POST_HEADERS)
    return result.json()

def get_token_json(location, params=None):
    """
    Performs a GET using the passed URL location
    """
    result = requests.get(
        location,
        params=params,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=TOKEN_HEADERS)
    return result.json()

def get_non_json(location, params=None):
    """
    Performs a GET using the passed URL location
    """
    print params
    result = requests.get(
        location,
        params=params,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=POST_HEADERS)
    print result.url
    return result

def post_json(location, json_data):
    """
    Performs a POST and passes the data to the URL location
    """

    result = requests.post(
        location,
        data=json_data,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=POST_HEADERS)

    return result.json()

def post_token_json(location, json_data):
    """
    Performs a POST and passes the data to the URL location
    """

    result = requests.post(
        location,
        data=json_data,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=TOKEN_HEADERS)
    return result.json()

def put_json(location, json_data):
    """
    Performs a POST and passes the data to the URL location
    """

    result = requests.put(
        location,
        data=json_data,
        auth=(USERNAME, PASSWORD),
        verify=SSL_VERIFY,
        headers=POST_HEADERS)

    return result.json()

parser = argparse.ArgumentParser(description="Tag a host in ManageIQ")
parser = argparse.ArgumentParser(add_help=True)

group = parser.add_mutually_exclusive_group()
group.add_argument('-a', '--add', action='store_true')
group.add_argument('-r', '--remove', action='store_true')
parser.add_argument('-n', '--name', dest='hostname', type=str,
                    required=True, help="Hostname to assign")
parser.add_argument('-d', '--dest', dest='department', type=str,
                    required=True,
                    help="Department category to assign to i.e. web_trading_platform")

args = parser.parse_args()

if args.add:
    ACTION = "assign"

if args.remove:
    ACTION = "unassign"

HOSTNAME = args.hostname
DEPARTMENT = "/managed/department/%s" % args.department

USERNAME = 'admin'
PASSWORD = 'smartvm'

#Test out the organization to make sure we can connect nad we're working with the right one.
auth = get_json(MIQ_API + "auth/")
current_token = auth['auth_token']

TOKEN_HEADERS = {'X-Auth-Token' : current_token, 'Content-Type': 'application/json'}

host_tags = get_token_json(MIQ_API + "vms?expand=tags,resources&filter[]=name='%s'&attributes=name,vendor" % HOSTNAME)
tags_list = get_token_json(MIQ_API + "tags?expand=resources&filter[]=name='%s'&attributes=name,id" % DEPARTMENT)

host_ok = False

for names in host_tags['resources']:
    miq_host_name = names['name']
    miq_host_href = names['href']
    miq_host_id = names['id']
    for tags in names['tags']:
        host_ok = True
        if args.add:
            if "department" not in tags['name']:
                continue
            else:
                print "Hostname: %s already has a department Tag: %s" % (HOSTNAME, tags['name'].rsplit('/', 1)[1])
                sys.exit(0)

if host_ok is not True:
    print "Host doesn't exist"
    sys.exit(-1)

if tags_list['subcount'] == 0:
    print "Supplied department tag name: %s doesn't exist" % args.department
    sys.exit(-1)

for tags in tags_list['resources']:
    miq_tags_name = tags['name']
    miq_tags_href = tags['href']
    miq_tags_id = tags['id']

json_payload = {
    "action": ACTION,
    "resources" : [
        {"category" : "department", "name" : args.department}
    ]
    }

post_url = MIQ_API + "vms/" + str(miq_host_id) + "/tags"

assign_tag = post_token_json(post_url, json.dumps(json_payload))
print assign_tag['results'][0]['message']
