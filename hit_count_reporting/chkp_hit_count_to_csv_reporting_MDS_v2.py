from __future__ import print_function
import json, http.client, ssl
import sys, os, re
import getpass
from datetime import datetime, date
import datetime
import csv

"""
Author: Joe Audet
Date Created: 2022NOV02
Last Modified: 2024AUG15
Ver: 0.92

Usage:
This script will login to a Check Point management server and retrieve all of the non-shared and non-inline access policy layers, then present 
a menu where the user can select a policy (or all), which will create a CSV output for each selected rulebase

2024AUG - Reconfigure existing functions to make script MDS capable in addition to running on SMS
        - Add selection menu for domains
        - 
"""

#Header line to insert into the top of each CSV
csv_header=["LAYER_NAME","RULE_NUMBER","RULE_NAME","HIT_COUNT","DATE_LAST_HIT","DAYS_SINCE_LAST_HIT","RULE_ENABLED","MODIFIED_DATE","MODIFIED_BY","RULE_UID"]

#Get today's date
todays_date = date.today()
username = ''
password = ''
policy_info = []
mgmt_server = ''
all_policies_object = {"name" : "Collect All Policies", "uid" : "n/a"}
all_rules_object = []
exit_object = {"name" : "Exit", "uid" : "n/a"}
session_id = ''
domain_specific_session_id = ''
last_hit_empty='No last hit to show date for'
first_hit_empty='No first hit to show date for'
last_delta_empty='No last hit to compare'
first_delta_empty='No first hit to compare'
is_mds=False
domain_names = []
active_domain_name = ''

#csv_file_name='demo_csv_output.csv'

def main():
  # getting server / login details from the user
  global mgmt_server,username,password
  mgmt_server = input("Enter server IP address [Press ENTER for localhost]:")
  if mgmt_server == '':
    mgmt_server = '127.0.0.1'
  print(f'Connecting to Management Server IP: {mgmt_server}')

  username = input("Enter username (Press ENTER to use admin): ")
  if username == '':
    username = 'admin'

  if sys.stdin.isatty():
    password = getpass.getpass(f"Enter password for {username}: ")
  else:
    print("Attention! Your password will be shown on the screen!")
    password = input(f"Enter password for {username}: ")

  #Login to mgmt server - store session ID for subsequent calls and logout
  session_id = login(username,password,'')

  #Check if the server we are connecting to is an MDS
  check_if_mds(session_id)
  
  #If MDS, loop domains and create a selection menu, if not go right to policy loop
  if (is_mds):
    create_interactive_domain_list_menu(session_id)
  else:
    create_interactive_access_policy_menu(session_id)

def check_if_mds(sid):
  global is_mds
  payload = json.dumps({ })
  response = api_call(mgmt_server, "show-mdss", payload, sid)
  response_data = response.read()

  #Set is_mds to True if show-mdss call returns a 200, SMS will return a 404 error of command cannot be run unless on MDS
  if response.status == 200:
    is_mds=True
  else:
    print("SMS server, skipping domain selection screen\n")
    print('Error occurred while trying to show-mdss: {}'.format(response_data.decode('utf-8')))

def create_interactive_domain_list_menu(sid):
  global domain_names,domain_specific_session_id,active_domain_name
  domain_names = get_domain_names(sid)
  clear_console()
  print_domain_names()

  while True:
    selected_domain_number = user_selected_domain_number()
    try:
        #policy_info[selected_policy_number]
        if (domain_names[selected_domain_number]["name"] == 'Exit'):
          logout(sid)
          break
        else:
          clear_console()
          domain_name = domain_names[selected_domain_number]['name'].replace(' ','_')
          print(f"Processing domain: {domain_name}")
          active_domain_name = domain_name
          domain_specific_session_id = login(username,password,domain_name)
          create_interactive_access_policy_menu(domain_specific_session_id)
          print_domain_names()
          continue

    except ValueError:
      clear_console()
      print(f"You entered {selected_domain_number} which is an invalid selection, please enter a valid policy number")
      print_domain_names()
      continue
    except IndexError:
      clear_console()
      print(f"You entered {selected_domain_number} which is an invalid selection, please enter a valid policy number")
      print_domain_names()
      continue

def get_domain_names(sid):
  domain_names = []
  payload = json.dumps({ })
  # Get names of domains - store for iteration
  response = api_call(mgmt_server, 'show-domains', payload, sid)
  data = response.read()
  if response.status == 200:
    response_data = json.loads(data.decode('utf-8'))
    for domain in response_data['objects']:
      domain_names.append({"name": domain["name"]})

    #Add this as final entry for users to cleanly close out of the loop
    domain_names.insert(len(domain_names),exit_object)
    return domain_names
  else:
    print('Error occurred while trying to show-domains: {}'.format(data.decode('utf-8')))
    logout(sid)
    sys.exit()  

def print_domain_names():
  print("\n===== Domain Names =====")
  domain_counter = 0
  for domain in domain_names:
      print(str(domain_counter) + " - " + domain["name"])
      domain_counter+=1
  print("\n")

# Display a list of all access policies for the user to select from, including an option for 'All Policies' and an 'Exit' option
def create_interactive_access_policy_menu(sid):
  #Create list of non shared layers name and uid fields (shared layers will be accessed by their UID which is in key 'inline-layer' within the 'show-access-rulebase' output)
  global policy_info
  policy_info = get_non_shared_access_layer_names(sid)
  clear_console()
  print_policy_names()

  while True:
    selected_policy_number = user_selected_policy_number()
    try:
        policy_info[selected_policy_number]
        if (policy_info[selected_policy_number]["name"] == 'Exit'):
          logout(sid)
          break
        elif (policy_info[selected_policy_number]["name"] == all_policies_object["name"]):
          for policy in policy_info:
              if policy["name"] == all_policies_object["name"] or policy["name"] == exit_object["name"]:
                continue
              else:
                policy_name = policy['name'].replace(' ','_')
                print(f"Processing access-layer: {policy_name}")
                loop_policy_rulebase(policy["uid"], policy_name,sid)
          print_policy_names()
          continue
        else:
          #clear_console()
          policy_name = policy_info[selected_policy_number]['name'].replace(' ','_')
          print(f"Processing access-layer: {policy_name}")
          loop_policy_rulebase(policy_info[selected_policy_number]["uid"], policy_name,sid)
          print_policy_names()
          continue

    except ValueError:
      clear_console()
      print(f"You entered {selected_policy_number} which is an invalid selection, please enter a valid policy number")
      print_policy_names()
      continue
    except IndexError:
      clear_console()
      print(f"You entered {selected_policy_number} which is an invalid selection, please enter a valid policy number")
      print_policy_names()
      continue

def get_non_shared_access_layer_names(sid):
  access_layer_names = [all_policies_object]
  payload = json.dumps({
    "details-level": "full"
  })
  # Get names of access layers - store for iteration
  response = api_call(mgmt_server, 'show-access-layers', payload, sid)
  data = response.read()
  if response.status == 200:
    response_data = json.loads(data.decode('utf-8'))
    for accesslayer in response_data['access-layers']:
      if (accesslayer['shared']):
        print('Skipping Shared Layer - {}'.format(accesslayer["name"]))
        continue
      if 'parent-layer' in accesslayer:
        print('Skipping Inline Layer - {}'.format(accesslayer["name"]))
        continue
      access_layer_names.append({"name": accesslayer["name"], "uid" : accesslayer["uid"]})

    #Add this as final entry for users to cleanly close out of the loop
    access_layer_names.insert(len(access_layer_names),exit_object)
    return access_layer_names
  else:
    print('Error occurred while trying to show-access-layers: {}'.format(data.decode('utf-8')))
    logout(sid)
    sys.exit()  

def user_selected_policy_number():
  while True:
      policy_num = input("Please enter the number of the policy to report hit usage on: ")
      if (check_user_input(policy_num, 'int',"policy")):
        return int(policy_num)

def user_selected_domain_number():
  while True:
      domain_num = input("Please enter the number of the domain to list policies in: ")
      if (check_user_input(domain_num, 'int',"domain")):
        return int(domain_num)

def check_user_input(input, type,menu):
  if type == 'int':
    try:
      # Convert it into integer
      val = int(input)
      return True
    except ValueError:
      clear_console()
      if menu == "policy":
        print(f"You entered {input} which is an invalid selection, please enter a valid policy number from the list\n")
        print_policy_names()
      elif menu == "domain":
        print(f"You entered {input} which is an invalid selection, please enter a valid domain number from the list\n")
        print_domain_names()
      return False

def clear_console():
  os.system('clear')

def print_policy_names():
  print("\n===== Policy Rule Hit Reporting =====")
  policy_counter = 0
  for policy in policy_info:
      print(str(policy_counter) + " - " + policy["name"])
      policy_counter+=1
  print("\n")

def convert_datestring_to_date(datestr):
  str = re.search(r'\d{4}-\d{2}-\d{2}', datestr)
  return datetime.datetime.strptime(str.group(), '%Y-%m-%d').date()

def loop_policy_rulebase(policyuid,policy_name,sid):
  finished = False  # will become true after getting all the data
  #all_objects = {}  # accumulate all the objects from all the API calls
  global all_rules_object
  all_rules_object = []
  all_rules_object.append(csv_header)
  iterations = 0  # number of times we've made an API call
  limit = 50 # page size to get for each api call
  offset = 0 # skip n objects in the database
  payload = {}

  payload = json.dumps({"limit": limit, "offset": iterations * limit + offset, "uid" : policyuid, "details-level" : "standard", "show-hits" : True})
  response = api_call(mgmt_server, "show-access-rulebase", payload, sid)
  response_data = response.read()

  if response.status == 200:
    response_data = json.loads(response_data.decode('utf-8'))
    loop_rules(response_data,'','',sid)

    while not finished:
      total_objects = response_data['total']  # total number of objects
      received_objects = response_data['to']  # number of objects we got so far

      if received_objects == total_objects:
        break

      iterations += 1
      
      payload = json.dumps({"limit": limit, "offset": iterations * limit + offset, "uid" : policyuid, "details-level" : "standard", "show-hits" : True})
      response = api_call(mgmt_server, "show-access-rulebase", payload, sid)
      response_data = response.read()
      response_data = json.loads(response_data.decode('utf-8'))
      loop_rules(response_data,'','',sid)
    
    print_rules(policy_name)

  else:
    print('Error occurred while trying to show-access-rulebase: {}'.format(response_data.decode('utf-8')))

def loop_rules(data, parent_rule_number, policy_name, sid):
  #Due to how access-sections work, we need to store the policy name from the access-rulebase object and pass it back if an access-section is present when
  #we loop through the sub-array because the nested object has no copy of the rulebase name to reference
  if not policy_name:
    policy_name = data['name']
  global all_rules_object
  for access_rule in data['rulebase']:
    if (access_rule['type'] == 'access-section'):
      #If an access-section is present it output the rules of the section as an array within the object, so we have to interate that sub-array to print those rules
      loop_rules(access_rule,'',policy_name,sid)
    else:
      if 'name' in access_rule:
        rule_name = access_rule['name'].replace('\n',' ')
      else:
        rule_name ='Empty Rule Name'

      if 'last-date' in access_rule['hits']:
        last_hit_date = convert_datestring_to_date(access_rule['hits']['last-date']['iso-8601'])
        last_delta=str((todays_date - last_hit_date).days)
        #first_hit_date = convert_datestring_to_date(access_rule['hits']['first-date']['iso-8601'])
        #first_delta=str((todays_date - first_hit_date).days)
      else:
        last_hit_date = last_hit_empty
        last_delta = last_delta_empty
        #first_hit_date = first_hit_empty
        #first_delta = first_delta_empty
      
      if 'inline-layer' in access_rule:
        is_layer='Yes'
        #layer_uid=access_rule['inline-layer']
      else:
        is_layer='No'
        #layer_uid='Not inline layer'

      if parent_rule_number:
        rule_number = str(parent_rule_number) + '.' + str(access_rule['rule-number'])
      else:
        rule_number = str(access_rule['rule-number'])

      last_modified_date = convert_datestring_to_date(access_rule['meta-info']['last-modify-time']['iso-8601'])

      all_rules_object.append([policy_name,rule_number,rule_name,str(access_rule['hits']['value']),str(last_hit_date),last_delta,access_rule['enabled'],last_modified_date,access_rule['meta-info']['last-modifier'],access_rule['uid']])
      if (is_layer == 'Yes'):
        get_inline_layer_info(access_rule['inline-layer'], sid, rule_number)

    
def get_inline_layer_info(uid,sid,rulenumber):
  finished = False  # will become true after getting all the data
  iterations = 0  # number of times we've made an API call
  limit = 50 # page size to get for each api call
  offset = 0 # skip n objects in the database
  payload = json.dumps({"limit": limit, "offset": iterations * limit + offset, "uid" : uid, "details-level" : "standard", "show-hits" : True})
  response = api_call(mgmt_server, 'show-access-rulebase', payload, sid)
  response_data = response.read()
  if response.status == 200:
    response_data = json.loads(response_data.decode('utf-8'))
    loop_rules(response_data,rulenumber,'',sid)

    while not finished:
      total_objects = response_data['total']  # total number of objects
      received_objects = response_data['to']  # number of objects we got so far

      if received_objects == total_objects:
        break

      iterations += 1
      
      payload = json.dumps({"limit": limit, "offset": iterations * limit + offset, "uid" : uid, "details-level" : "standard", "show-hits" : True})
      response = api_call(mgmt_server, "show-access-rulebase", payload, sid)
      response_data = response.read()
      response_data = json.loads(response_data.decode('utf-8'))
      loop_rules(response_data,rulenumber,'',sid)
      
  else:
    print('Error occurred while trying to inline layer: {}'.format(response_data.decode('utf-8')))

def print_rules(policy_name):

  directory_path = os.getcwd()

  if (is_mds):
    csv_file_name= active_domain_name+"_"+policy_name+"_hit_count_report"+'_{:%Y%b%d_%H%M}'.format(datetime.datetime.now())+".csv"
  else:
    csv_file_name= policy_name+"_hit_count_report"+'_{:%Y%b%d_%H%M}'.format(datetime.datetime.now())+".csv"

  if os.path.exists(csv_file_name):
    os.remove(csv_file_name)

  with open(csv_file_name, 'w') as file:
    writer = csv.writer(file, dialect='excel')
    writer.writerows(all_rules_object)
  
  print(f"Created CSV output file: {directory_path}/{csv_file_name}")

def login(username,password,domainname):
  sessnam = username+'_{:%Y%b%d%H%M%S}'.format(datetime.datetime.now())
  payload = json.dumps({
    'user': username,
    'password': password,
    'session-name' : sessnam,
    "domain" : domainname
  })

  response = api_call(mgmt_server, 'login', payload, '')
  data = response.read()

  if response.status == 200:
    response_data = json.loads(data.decode('utf-8'))
    session_id=response_data['sid']
    print('Login Successful - Session ID: {}'.format(session_id))
    return session_id
  else:
    print('Error occurred while trying to login: {}'.format(data.decode('utf-8')))
    sys.exit()

def logout(sid):
  payload = json.dumps({})
  response = api_call(mgmt_server, 'logout', payload, sid)
  data = response.read()

  if response.status == 200:
    response_data = json.loads(data.decode('utf-8'))
    logout_message=response_data['message']
    print('Logout of Session ID: ' + sid + ' ' + logout_message)
  else:
    print('Error occurred while trying to logout: {}'.format(data.decode('utf-8')))
    sys.exit()

def api_call(ip_addr, command, json_payload, sid):
  #Use SSLContect object to disable certificate verification allowing self signed certs
  context = ssl.SSLContext()
  context.check_hostname = False
  context.verify_mode = ssl.CERT_NONE
  conn = http.client.HTTPSConnection(ip_addr, context=context )

  if command == 'login':
    request_headers = {'Content-Type' : 'application/json'}
  else:
    request_headers = {'Content-Type' : 'application/json', 'X-chkp-sid' : sid}

  #We have left the vX.X out of the API call to ensure it uses the latest version
  conn.request("POST", "/web_api/{}".format(command), json_payload, request_headers)
  res = conn.getresponse()
  return res

if __name__ == "__main__":
    main()