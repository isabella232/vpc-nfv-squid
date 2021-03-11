#!/bin/bash
set -e

success=false
trap check_finish EXIT
check_finish() {
  if [ $success = true ]; then
    echo '>>>' success
  else
    echo "FAILED"
  fi
}

echo ">>> Targeting region $TF_VAR_region ..."
ibmcloud target -r $TF_VAR_region 

echo ">>> Targeting resource group $TF_VAR_resource_group_name ..."
ibmcloud target -g $TF_VAR_resource_group_name 

echo ">>> Setting VPC Gen for compute..."
if ibmcloud is >/dev/null; then
  ibmcloud is target --gen 2
else
  echo "Make sure vpc-infrastructure plugin is properly installed with ibmcloud plugin install vpc-infrastructure."
  exit 1
fi

echo ">>> Is terraform installed?"
terraform version

echo ">>> Is curl installed?"
curl -V

success=true
