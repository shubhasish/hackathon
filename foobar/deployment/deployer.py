import boto3
import yaml
import os
import sys
import logging
import time



logging.basicConfig(format='%(levelname)s: %(message)s',stream=sys.stdout, level=logging.INFO)

################# Constants

s3_bucket = "ecs.deployment"

########## Functions
def print_deployment(env,service_name,version,memoryconfig,cpuconfig):
    logging.info("###########################################################")
    logging.info("Environment:\t%s"%env)
    logging.info("Service Name:\t%s"%service_name)
    logging.info("Service Version:\t%s"%version)
    logging.info("Minimum Memory:\t%s"%memoryconfig[0])
    logging.info("Maximum Memory:\t%s"%memoryconfig[1])
    logging.info("Cpu:\t%s"%cpuconfig)
    logging.info("##########################################################\n\n")


def uploadFile(client):
    file_list = set(os.listdir(os.path.dirname(os.path.abspath(__file__))))

    file_list.remove(os.path.basename(__file__))
    for file in file_list:
        upload_result = client.s3Upload(file)
        if upload_result:
            pass
        else:
            logging.error(upload_result)
            os._exit(1)
class client:
    def __init__(self,type,region):
        self.client = boto3.client(type,region_name=region)

    def check_s3(self,path):
        try:
            self.client.get_object(Bucket=s3_bucket,Key=path)
            return True
        except Exception as e:
            if "key does not exist" in e.message:
                return False
            else:
                return e.message

    def create_bucket(self,path):
        try:
            self.client.put_object(Bucket=s3_bucket,Body="",Key=path)
            return True
        except Exception as e:
            return e.message
    def s3Upload(self,file):
        try:
            file_path = os.path.dirname(os.path.abspath(__file__)) + '/' + file
            self.client.upload_file(Bucket=s3_bucket,Filename=file_path,Key=(bucket_path+file))
            return True
        except Exception as e:
            return e.message

    def doesStackExist(self,stackName):
        try:
            self.client.describe_stacks(StackName=stackName)
            return True
        except Exception as e:
            if "Stack with id %s does not exist" % stack_name in e.message:
                return False
            else:
                return e.message

    def create_stack(self,stackName):
        try:
            stack = self.client.create_stack(StackName=stackName,TemplateURL=deployment_path,Parameters=parameters,Capabilities=['CAPABILITY_NAMED_IAM'])
            return (True,stack)
        except Exception as e:
            return (False,e.message)

    def update_stack(self,stackName):
        try:
            stack = self.client.update_stack(StackName=stackName,TemplateURL=deployment_path,Parameters=parameters,Capabilities=['CAPABILITY_NAMED_IAM'])
            return (True,stack)
        except Exception as e:
            return (False,e.message)

    def get_stack_updates(self, stackName):
        try:
            stack = self.client.describe_stacks(StackName=stackName)
            return (True, stack)
        except Exception as e:
            return (False, e.message)

### Input


arguments = sys.argv
dict = {}
for x in range(1,len(arguments)):
    arg = arguments[x].split('=')
    dict[arg[0]] = arg[1]

logging.info("\nStarting Application deployemnt to %s\n"%dict['env'])
logging.info("Searching for 'deployment.yaml' in your deployment folder.")
deployment_file = os.path.dirname(os.path.abspath(__file__)) + "/deployment.yaml"
if os.path.isfile(deployment_file):

    logging.info("deployment.yaml found !!!\n")

    stream = open(deployment_file,"r+")
    yaml = yaml.safe_load(stream)

    service_name = yaml['Parameters']['Application']['Default']
    container_definitions = yaml['Resources']['TaskDefinition']['Properties']['ContainerDefinitions'][0]
    version = dict['version']
    min_memory = container_definitions['MemoryReservation']
    max_memory = container_definitions['Memory']
    cpu= container_definitions["Cpu"]
    print_deployment(dict['env'],service_name,version,(min_memory,max_memory),cpu)




    stack_name = "%s-%s"%(dict['env'],service_name)
    s3_link = "https://s3.amazonaws.com/"
    bucket_path = 'deployment/%s/%s/'%(dict['env'],service_name)
    s3_path = s3_link+bucket_path

#########
    deployment_path = "https://s3.amazonaws.com/%s/deployment/%s/%s/deployment.yaml"%(s3_bucket,dict['env'],service_name)
############################
    parameters = [{'ParameterKey':'Cluster','ParameterValue':dict['env']},{'ParameterKey':'Version','ParameterValue':dict['version']}]

########################
    s3_client = client('s3',region=dict['region'])
    logging.info("Checking your deployment folder in s3 bucket %s\n"%s3_bucket)
    check_result = s3_client.check_s3(bucket_path)

    if check_result == True:
        logging.info("Deployment folder found")
        logging.info("Uploading all required yaml files to s3")
        uploadFile(s3_client)
    elif check_result == False:
        logging.info("No Deployment folder found. Creating a new one for you.")
        create_result = s3_client.create_bucket(bucket_path)
        if create_result:
            logging.info("Uploading all required yaml files")
            uploadFile(s3_client)
        else:
            logging.info(create_result)
            os._exit(1)
    elif "credentials" in check_result:
        logging.error(check_result)
        logging.error("\n\nCredentials not supported\"")
        os._exit(1)
    else:
        logging.error(check_result)
        os._exit(1)


    cloudformation_client = client('cloudformation',region=dict['region'])

    getStack = cloudformation_client.doesStackExist(stack_name)

    if getStack==True:
        logging.info("Service already present in the cluster. Upgrading new configurations\n")
        update_result = cloudformation_client.update_stack(stack_name)
        if update_result[0]:
            logging.info("New configurations updated\n")
            logging.info("Check you stack.Stack Id: %s"%update_result[1]['StackId'])

        else:
            logging.error(update_result[1])
            os._exit(1)
    elif getStack==False:
        logging.info("Deploying your Application\n")
        create_result = cloudformation_client.create_stack(stack_name)
        if create_result[0]:
            logging.info("Application Deployed\n")
            logging.info("Check you stack.Stack Id: %s" % create_result[1]['StackId'])
        else:
            logging.error(create_result[1])
            os._exit(1)

    while True:
        result = cloudformation_client.get_stack_updates(stack_name)
        if result[0]:
            stack_status = result[1]['Stacks'][0]['StackStatus']
            logging.info("%s current status is %s\n" % (stack_name, stack_status))
            if stack_status in ['CREATE_FAILED', 'ROLLBACK_IN_PROGRESS', 'ROLLBACK_FAILED', 'DELETE_IN_PROGRESS',
                                'DELETE_FAILED', 'UPDATE_ROLLBACK_IN_PROGRESS', 'UPDATE_ROLLBACK_FAILED']:
                logging.error("Stack upgradation failed for %s." % stack_name)
                logging.error("You would like to check AWS console for more details")
                logging.error("Exiting the script with failure\n\n")
                os._exit(1)
            elif stack_status in ['CREATE_IN_PROGRESS', 'UPDATE_IN_PROGRESS', 'REVIEW_IN_PROGRESS',
                                  'UPDATE_COMPLETE_CLEANUP_IN_PROGRESS',
                                  'UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS']:
                logging.info("The  stack creation/upgradation for  %s is in progress...." % stack_name)
                logging.info("Agent will check the stack status again after 10s, sleeping for 10s\n\n")
                time.sleep(10)
                continue
            elif stack_status in ['CREATE_COMPLETE', 'ROLLBACK_COMPLETE', 'DELETE_COMPLETE', 'UPDATE_COMPLETE',
                                  'UPDATE_ROLLBACK_COMPLETE']:
                logging.info("Stack upgradation successful for %s\n\n" % stack_name)
                break

        else:
            logging.error("Mayday !!! No such Stack found.")
            logging.error("Exiting the script with failure")
            os._exit(1)
else:
    logging.error("No file found")
    os._exit(1)