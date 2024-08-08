import os
import boto3
import requests
import snowflake.connector as sf


def lambda_handler(event, context):

    url = 'https://de-materials-tpcds.s3.ca-central-1.amazonaws.com/inventory.csv'
    destination_folder = '/tmp'
    file_name = 'inventory.csv'
    local_file_path = '/tmp/inventory.csv'

    # Snowflake connection parameters
    account = os.environ['account']
    warehouse = os.environ['warehouse']
    database = os.environ['database']
    schema = os.environ['schema']
    table = os.environ['table']
    user = os.environ['user']
    password = os.environ['password']
    role = os.environ['role']
    stage_name = os.environ['stage_name']

    # Download the data from the API endpoint
    response = requests.get(url)
    response.raise_for_status()

    # Save the data to the destination file in /tmp directory
    file_path = os.path.join(destination_folder, file_name)
    with open(file_path, 'wb') as file:
        file.write(response.content)

    with open(file_path, 'r') as file:
        file_content = file.read()
        print("File Content:")
        print(file_content)

    # Establish Snowflake connection
    conn = sf.connect(user=user, password=password,
                      account=account, warehouse=warehouse,
                      database=database,  schema=schema,  role=role)

    cursor = conn.cursor()

    # use schema
    use_schema = f"use schema {schema};"
    cursor.execute(use_schema)

    # create CSV format
    create_csv_format = f"CREATE or REPLACE FILE FORMAT COMMA_CSV TYPE ='CSV' FIELD_DELIMITER = ',';"
    cursor.execute(create_csv_format)

    create_stage_query = f"CREATE OR REPLACE STAGE {stage_name} FILE_FORMAT =COMMA_CSV"
    cursor.execute(create_stage_query)

    # Copy the file from local to the stage
    copy_into_stage_query = f"PUT 'file://{local_file_path}' @{stage_name}"
    cursor.execute(copy_into_stage_query)

    # List the stage
    list_stage_query = f"LIST @{stage_name}"
    cursor.execute(list_stage_query)

    # truncate table
    truncate_table = f"truncate table {schema}.{table};"
    cursor.execute(truncate_table)

    # Load the data from the stage into a table (example)
    copy_into_query = f"COPY INTO {schema}.{table} FROM @{stage_name}/{file_name} FILE_FORMAT =COMMA_CSV;"
    cursor.execute(copy_into_query)

    print("File uploaded to Snowflake successfully.")

    return {
        'statusCode': 200,
        'body': 'File downloaded and uploaded to Snowflake successfully.'
    }
