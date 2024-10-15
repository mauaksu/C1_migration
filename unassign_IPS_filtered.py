#!/bin/env/python

import argparse
import sys
import requests
import os
import logging

# change the URL if workload protection instance (workload security) is in different region
C1URL = 'https://workload.de-1.cloudone.trendmicro.com/api'

# workload security api key (not c1 api key), assuming there is only 1 workload security tenant
API_KEY = os.getenv('API_KEY')
# API_KEY = "paste API key here if you don't want to use any environemnt variable"

def get_ips_rules():
    headers = {
        'Content-Type': 'application/json',
        'api-version': 'v1',
        'api-secret-key': API_KEY,
    }

    rules = []
    min_id = 0
    while True:
        payload = {
            'maxItems': 5000,
            'searchCriteria': [
                {
                    'idTest': 'greater-than',
                    'idValue': min_id,
                }
            ],
            'sortByObjectID': True,
        }

        # using search API to get around 5000 items limit
        url = C1URL + '/intrusionpreventionrules/search'

        response = requests.post(url, headers=headers, json=payload)

        if response.status_code == 200:
            logging.debug(f'listed ips rules for one batch')
            rules += response.json()['intrusionPreventionRules']
        else:
            logging.error(f'error: get_ips_rules returns {response.status_code}')
            exit(1)

        if len(response.json()['intrusionPreventionRules']) == 0:
            break

        min_id = response.json()['intrusionPreventionRules'][-1]['ID']

    return rules


def get_computer_ips_rule_assignments(computer_id, override=True):
    headers = {
        'api-version': 'v1',
        'api-secret-key': API_KEY,
    }

    ids = []
    # using search API to get around 5000 items limit
    url = C1URL + f'/computers/{computer_id}/intrusionprevention/assignments?override={str(override).lower()}'

    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        logging.debug(f'listed computer ips rule assignments for {computer_id}')
        ids += response.json()['assignedRuleIDs']
    else:
        logging.error(f'error: get_computer_ips_rule_assignments returns {response.status_code}')

    return ids


def get_computers():
    headers = {
        'Content-Type': 'application/json',
        'api-version': 'v1',
        'api-secret-key': API_KEY,
    }

    computers = []
    min_id = 0
    while True:
        payload = {
            'maxItems': 5000,
            'searchCriteria': [
                {
                    'idTest': 'greater-than',
                    'idValue': min_id,
                },
                {
                    'fieldName': 'policyID',
                        'numericTest': 'in',
                        'numericValueList': [
                            34,
                            70,
                            199,
                            232
                        ]
                }
            ],
            'sortByObjectID': True,
        }

        # using search API to get around 5000 items limit
        url = C1URL + '/computers/search'

        response = requests.post(url, headers=headers, json=payload)

        if response.status_code == 200:
            logging.debug(f'listed computers with min ID {min_id}')
            computers += response.json()['computers']
        else:
            logging.error(f'error: get_computers returns {response.status_code}')
            exit(1)

        if len(response.json()['computers']) == 0:
            break

        min_id = response.json()['computers'][-1]['ID']

    return computers


def organize_rules_by_id(ips_rules):
    """
    return a dict: IPS rule identifier -> id
    """
    rule_id_dict = {}

    for rule in ips_rules:
        rule_id = rule.get('ID')
        rule_identifier = rule.get('identifier')
        rule_id_dict[rule_id] = rule

    return rule_id_dict


def organize_hostid_by_guid():
    """
    return a dict from host GUID (agent GUID) to host ID
    """
    host_id_dict = {}

    headers = {
        'Content-Type': 'application/json',
        'api-version': 'v1',
        'api-secret-key': API_KEY,
    }

    url = C1URL + '/computers?expand=none'

    response = requests.get(url, headers=headers)
    for computer in response.json().get('computers'):
        # WS uses upper case host GUID, but V1 uses lower case
        host_id_dict[computer['hostGUID'].lower()] = computer['ID']

    return host_id_dict

def set_ips_rules_to_computer(computer_id, rule_ids, dryrun, override=True):
    logging.info(f'setting rule_ids {rule_ids} to computer_id {computer_id}')
    resps = []
    headers = {
        'Content-Type': 'application/json',
        'api-version': 'v1',
        'api-secret-key': API_KEY,
    }

    payload = {
        'ruleIDs': rule_ids,
    }

    url = C1URL + f'/computers/{computer_id}/intrusionprevention/assignments?overrides={str(override).lower()}'
    if dryrun:
        return resps

    response = requests.put(url, headers=headers, json=payload)
    if response.status_code == 200:
        logging.info(f'set new rule_ids to computer_ids {computer_id} successfully')
        resps.append(response.json())
    else:
        logging.error(f'error: set_ips_rules_to_computer returns {response.status_code}')

    return resps


# host_id_dict and rule_id_dict may be different with different WS tenants
def handle(computers, id_rule_dict, advanced_rule_id_set, dryrun=True):
    num_processed = 0
    for computer in computers:
        computer_id = computer['ID']

        hostname = computer['hostName']
        rule_ids = get_computer_ips_rule_assignments(computer_id)
        if len(rule_ids) > 0:
            logging.info(f'computer {computer_id} ({hostname}) has rules {rule_ids}')
        rule_diff = set(rule_ids) & advanced_rule_id_set
        if len(rule_diff) > 0:
            new_rule_ids = list(set(rule_ids) - advanced_rule_id_set)
            logging.info(f'To unassign advanced rule ids {rule_diff} from computer {computer_id}')
            for rid in rule_diff:
                rule = id_rule_dict[rid]
                if "identifier" in rule:
                    logging.info(f'{rid}: {rule["identifier"]} - {rule["name"]}')
                else:
                    logging.info(f'{rid}: {rule["name"]}')
            set_ips_rules_to_computer(computer_id, new_rule_ids, dryrun)
            logging.debug(f'computer {computer_id} now has IPS rules {new_rule_ids}')
            num_processed += 1

    return num_processed


def main():
    """
    Unassign advanced IPS rules from all computers.
    This script requires requests package. Please run "pip install requests" in advance to install the required package.
    Please update C1URL if needed.
    Before execution, a workload security API key has to be set as an environment variable "API_KEY".
    """
    parser = argparse.ArgumentParser(description='Unassign advanced IPS rules from computers')
    parser.add_argument("--dry-run", help="Don't invoke unassign rules API", action="store_true")
    parser.add_argument("--verbose", help="Print more detail logs", action="store_true")
    parser.add_argument("--computer-id", type=int, help="Specify a computer ID. The script will run against this computer only.")
    args = parser.parse_args()
    dryrun = args.dry_run

    if args.verbose:
        logging.basicConfig(filename='dry-run.txt', encoding='utf-8',level=logging.DEBUG)
    else:
        logging.basicConfig(filename='dry-run.txt', encoding='utf-8',level=logging.INFO)

    logging.info(f'This script will unassign all advanced IPS rules from computers. dry-run={dryrun}')
    computers = get_computers()
    if args.computer_id is not None:
        computers = [c for c in computers if c['ID'] == args.computer_id]
    logging.info(f'There are {len(computers)} computer(s) to process')

    ips_rules = get_ips_rules()
    advanced_ips_rules = [r for r in ips_rules if r['ruleAvailability'] == 'workload' or 'identifier' in r and r['identifier'] == '1011949']

    id_rules_dict = organize_rules_by_id(ips_rules)
    advanced_id_rules_dict = organize_rules_by_id(advanced_ips_rules)
    advanced_rule_id_set = set(advanced_id_rules_dict.keys())

    logging.debug(f'There are {len(advanced_rule_id_set)} advanced IPS rules')

    num_processed = handle(computers, id_rules_dict, advanced_rule_id_set, dryrun)
    logging.info(f'IPS rule assignments in {num_processed} computer(s) were processed. Script ends.')


if __name__ == '__main__':
    main()
