#!/bin/sh

usage () {
  echo "Usage:"
  echo "$0"
  exit 1
}

# check parameters
# REGION        - AWS region to use
# SEED          - Random seed that is part of the name of the AWS secret containing the db master password
# PROJECT_NAME  - Name of the project
# ENVIRONMENT   - stage or prod
# NAMESPACE     - The target k8s namespace to create a secret in
# DATABASE_TYPE - The type of database - mysql, postgres
# DATABASE_NAME - The name of the database(s) to create in the database server
# USER_NAME     - The name of the user to create and grant access to the database specified above
# USER_PASSWORD - The password of the user to create and grant access to the database specified above (optional)
# SECRET_NAME   - The suffix name of the secret created in AWS Secret Manager that will contain the created credentials
# CREATE_SECRET - A template file to render to create a secret (optional)
([[ -z "${REGION}" ]]        || \
 [[ -z "${SEED}" ]]          || \
 [[ -z "${PROJECT_NAME}" ]]  || \
 [[ -z "${ENVIRONMENT}" ]]   || \
 [[ -z "${NAMESPACE}" ]]     || \
 [[ -z "${SECRET_NAME}" ]]   || \
 [[ -z "${DATABASE_TYPE}" ]] || \
 [[ -z "${DATABASE_NAME}" ]] || \
 [[ -z "${USER_NAME}" ]] )  && \
echo "Some environment variables (REGION, SEED, PROJECT_NAME, ENVIRONMENT, NAMESPACE, SECRET_NAME, DATABASE_TYPE, DATABASE_NAME, USER_NAME) are not set properly." && usage

# docker image with postgres + mysql clients
DOCKER_IMAGE_TAG=commitdev/zero-k8s-utilities:0.0.3

# database info preparation
# this script will run both before and after make-apply-k8s, therefore the database service is not always available
DB_ENDPOINT=$(aws rds describe-db-instances --region=$REGION  --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}" --query "DBInstances[0].Endpoint.Address" | jq -r '.')
DB_NAME_LIST=$(echo ${DATABASE_NAME} | tr -dc 'A-Za-z0-9_ ') # used by job
DB_NAME=$(echo ${DB_NAME_LIST} | cut -d" " -f1) # used by db-pod
DB_TYPE=${DATABASE_TYPE}
## get rds master
SECRET_ID=$(aws secretsmanager list-secrets --region ${REGION}  --query "SecretList[?Name=='${PROJECT_NAME}-${ENVIRONMENT}-rds-${SEED}'].Name" | jq -r ".[0]")
MASTER_RDS_USERNAME=master_user
MASTER_RDS_PASSWORD=$(aws secretsmanager get-secret-value --region=${REGION} --secret-id=${SECRET_ID} | jq -r ".SecretString")
## get application user/pass
DB_APP_USERNAME=$(echo "${USER_NAME}" | tr -dc 'A-Za-z0-9')
DB_APP_PASSWORD=${USER_PASSWORD:-$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | base64 | head -c 24)}
JOB_ID=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)

# get correct dsn string for db type
if [[ "${DB_TYPE}" == "postgres" ]]; then
  DB_ENDPOINT_FOR_DSN="${DB_ENDPOINT}"
elif [[ "${DB_TYPE}" == "mysql" ]]; then
  DB_ENDPOINT_FOR_DSN="tcp(${DB_ENDPOINT})"
fi

# the manifest creates these things
# 1. Namespaces: db-ops, $NAMESPACE
# 2. Secret in db-ops: db-create-users (with master password, and a .sql file
# 3. Job in db-ops: db-create-users (runs the .sql file against the RDS given master_password from env)

# Run the job in the kubernetes cluster that will create the database user
eval "echo \"$(cat ./db-ops/job-create-db-${DATABASE_TYPE}.yml.tpl)\"" | kubectl apply -f -

# Create a secret in AWS Secrets Manager. The contents of this secret will be automatically pulled into a kubernetes secret by external-secrets
[[ -z "${CREATE_SECRET}" ]] || aws secretsmanager create-secret --name "${PROJECT_NAME}/kubernetes/${ENVIRONMENT}/${SECRET_NAME}" --description "Application secrets" --tags "[{\"Key\":\"application-secret\",\"Value\":\"${PROJECT}-${ENVIRONMENT}-${SECRET_NAME}\"}]" --secret-string "$(eval "echo \"$(cat ./db-ops/${CREATE_SECRET})\"")"

## Delete the entire db-ops namespace
kubectl -n db-ops wait --for=condition=complete --timeout=10s job db-create-users-$NAMESPACE-${JOB_ID}
if [ $? -eq 0 ]
then
    kubectl delete namespace db-ops
else
    echo "Failed to create application database user, please see 'kubectl logs -n db-ops -l job-name=db-create-users-$NAMESPACE-${JOB_ID}'"
    kubectl delete secret -n db-ops db-create-users
fi

