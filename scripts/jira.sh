#!/bin/bash

#
# A script to interact with Jira from the command line.
#
# Usage:
#   jira.sh get <TICKET_ID> - Get details for a specific ticket.
#   jira.sh list <PROJECT_KEY> - List open tickets for a project.
#
# Requirements:
#   - jq: This script uses jq to parse JSON responses. Install it with 'brew install jq'.
#   - Set the following environment variables in your ~/.zshrc or ~/.bash_profile:

# --- Configuration ---
# Check for required environment variables
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_USER" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "Error: Please set JIRA_URL, JIRA_USER, and JIRA_API_TOKEN environment variables."
  exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to use this script (e.g., 'brew install jq')."
    exit 1
fi

# --- Functions ---

# Function to show usage
usage() {
  echo "Usage: $0 {get <TICKET_ID> | list <PROJECT_KEY>}"
  exit 1
}

# Function to make authenticated API requests
jira_api_request() {
  local endpoint=$1
  local fields=${2:-} # Optional fields parameter, default to empty
  local url="${JIRA_URL}/rest/api/3/${endpoint}"

  if [ -n "$fields" ]; then
    url="${url}&fields=${fields}"
  fi

  curl -s -u "${JIRA_USER}:${JIRA_API_TOKEN}" \
       -H "Content-Type: application/json" \
       "${url}"
}

# Function to get a specific ticket
get_ticket() {
  local ticket_id=$1
  if [ -z "$ticket_id" ]; then
    echo "Error: Ticket ID is required."
    usage
  fi

  echo "Fetching details for ticket ${ticket_id}..."
  local response
  response=$(jira_api_request "issue/${ticket_id}")

  if echo "$response" | jq -e '.errorMessages' > /dev/null; then
    echo "Error fetching ticket:"
    echo "$response" | jq '.errorMessages[]'
    exit 1
  fi

  # Customize the output using jq
  echo "$response" | jq '{ 
    key: .key,
    summary: .fields.summary,
    status: .fields.status.name,
    assignee: .fields.assignee.displayName,
    reporter: .fields.reporter.displayName,
    created: .fields.created,
    updated: .fields.updated
  }'
}

# Function to list tickets for a project
list_project_tickets() {
  local project_key=$1
  if [ -z "$project_key" ]; then
    echo "Error: Project key is required."
    usage
  fi

  echo "Fetching open tickets for project ${project_key}..."
  # JQL to find open issues in the project
  local jql_raw="project = ${project_key} AND status != Done"
  response=$(jira_api_request "search?jql=${jql}")

  if echo "$response" | jq -e '.errorMessages' > /dev/null; then
    echo "Error fetching tickets:"
    echo "$response" | jq '.errorMessages[]'
    exit 1
  fi

  # Customize the output for the list
  echo "$response" | jq '.issues[] | {
    key: .key,
    summary: .fields.summary,
    status: .fields.status.name,
    assignee: .fields.assignee.displayName
  }'
}

# Function to list tickets assigned to the current user for a project
list_my_project_tickets() {
    local project_key=$1
    if [ -z "$project_key" ]; then
        echo "Error: Project key is required."
        usage
    fi

    echo "Fetching open tickets assigned to you for project ${project_key}..."
    # JQL to find open issues in the project assigned to the current user
    local jql="project = ${project_key} AND assignee = currentUser() AND status != Done"
    local response
    response=$(jira_api_request "search?jql=${jql}")

    if echo "$response" | jq -e '.errorMessages' > /dev/null; then
        echo "Error fetching tickets:"
        echo "$response" | jq '.errorMessages[]'
        exit 1
    fi

    # Customize the output for the list
    echo "$response" | jq '.issues[] | {
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name,
        assignee: .fields.assignee.displayName
    }'
}

# Function to list all projects
list_projects() {
    echo "Fetching all projects..."
    local response
    response=$(jira_api_request "project")

    if echo "$response" | jq -e 'if type=="object" and .errorMessages then .errorMessages else empty end' > /dev/null; then
        echo "Error fetching projects:"
        echo "$response" | jq '.errorMessages[]'
        exit 1
    fi

    # Customize the output for the list
    echo "$response" | jq '.[] | {
        key: .key,
        name: .name
    }'
}


# Function to list all tickets assigned to the current user across all projects
list_all_my_tickets() {
    echo "Fetching all projects..."
    local projects_response
    projects_response=$(jira_api_request "project")

    if echo "$projects_response" | jq -e 'if type=="object" and .errorMessages then .errorMessages else empty end' > /dev/null; then
        echo "Error fetching projects:"
        echo "$projects_response" | jq '.errorMessages[]'
        exit 1
    fi

    # Extract project keys
    local project_keys
    project_keys=$(echo "$projects_response" | jq -r '.[].key')

    for key in $project_keys; do
        list_my_project_tickets "$key"
    done
}


# Function to list unassigned tickets for a project
list_unassigned_tickets() {
    local project_key=$1
    if [ -z "$project_key" ]; then
        echo "Error: Project key is required."
        usage
    fi

    echo "Fetching unassigned tickets for project ${project_key}..."
    # JQL to find unassigned open issues in the project
    local jql_raw="project = ${project_key} AND assignee is EMPTY AND status = 'Ready For Development' AND priority IN (High, Highest, Medium)"
    local jql=$(echo "$jql_raw" | jq -sRr @uri)
    local response
    response=$(jira_api_request "search/jql?jql=${jql}&maxResults=5" "key,summary,status")

    if echo "$response" | jq -e '.errorMessages' > /dev/null; then
        echo "Error fetching tickets:"
        echo "$response" | jq '.errorMessages[]'
        exit 1
    fi

    # Customize the output for the list
    echo "$response" | jq '.issues[] | {
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name
    }'
}


# Function to list all statuses for a project
list_project_statuses() {
    local project_key=$1
    if [ -z "$project_key" ]; then
        echo "Error: Project key is required."
        usage
    fi

    echo "Fetching statuses for project ${project_key}..."
    local response
    response=$(jira_api_request "project/${project_key}/statuses")

    if echo "$response" | jq 'if type=="object" and .errorMessages then .errorMessages else empty end' > /dev/null; then
        echo "Error fetching statuses:"
        echo "$response" | jq '.errorMessages[]'
        exit 1
    fi

    # Customize the output for the list
    echo "$response" | jq '.[] | .statuses[] | {
        name: .name,
        id: .id
    }'
}


# Function to list all components for a project
list_project_components() {
    local project_key=$1
    if [ -z "$project_key" ]; then
        echo "Error: Project key is required."
        usage
    fi

    echo "Fetching components for project ${project_key}..."
    local response
    response=$(jira_api_request "project/${project_key}/components")

    if echo "$response" | jq 'if type=="object" and .errorMessages then .errorMessages else empty end' > /dev/null; then
        echo "Error fetching components:"
        echo "$response" | jq '.errorMessages[]'
        exit 1
    fi

    # Customize the output for the list
    echo "$response" | jq '.[] | {
        name: .name,
        id: .id
    }'
}

# --- Main Logic ---

COMMAND=$1
shift

case "$COMMAND" in
  get)
    get_ticket "$@"
    ;;
  list)
    list_project_tickets "$@"
    ;;
  list-mine)
    list_my_project_tickets "$@"
    ;;
  list-projects)
    list_projects "$@"
    ;;
  list-all-mine)
    list_all_my_tickets "$@"
    ;;
  list-unassigned)
    list_unassigned_tickets "$@"
    ;;
  list-project-statuses)
    list_project_statuses "$@"
    ;;
  list-project-components)
    list_project_components "$@"
    ;;
  *)
    usage
    ;;
esac
