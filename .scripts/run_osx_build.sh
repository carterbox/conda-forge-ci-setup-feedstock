#!/usr/bin/env bash

# -*- mode: jinja-shell -*-

source .scripts/logging_utils.sh

set -xe

MINIFORGE_HOME=${MINIFORGE_HOME:-${HOME}/miniforge3}

( startgroup "Installing a fresh version of Miniforge" ) 2> /dev/null

MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download"
MINIFORGE_FILE="Mambaforge-MacOSX-$(uname -m).sh"
curl -L -O "${MINIFORGE_URL}/${MINIFORGE_FILE}"
rm -rf ${MINIFORGE_HOME}
bash $MINIFORGE_FILE -b -p ${MINIFORGE_HOME}

( endgroup "Installing a fresh version of Miniforge" ) 2> /dev/null

( startgroup "Configuring conda" ) 2> /dev/null

source ${MINIFORGE_HOME}/etc/profile.d/conda.sh
conda activate base

mamba install --update-specs --quiet --yes --channel conda-forge --strict-channel-priority \
    pip mamba conda-build boa conda-forge-ci-setup=3
mamba update --update-specs --yes --quiet --channel conda-forge --strict-channel-priority \
    pip mamba conda-build boa conda-forge-ci-setup


conda uninstall --quiet --yes --force conda-forge-ci-setup
pip install --no-deps recipe/.

echo -e "\n\nSetting up the condarc and mangling the compiler."
setup_conda_rc ./ ./recipe ./.ci_support/${CONFIG}.yaml

if [[ "${CI:-}" != "" ]]; then
  mangle_compiler ./ ./recipe .ci_support/${CONFIG}.yaml
fi

if [[ "${CI:-}" != "" ]]; then
  echo -e "\n\nMangling homebrew in the CI to avoid conflicts."
  /usr/bin/sudo mangle_homebrew
  /usr/bin/sudo -k
else
  echo -e "\n\nNot mangling homebrew as we are not running in CI"
fi

echo -e "\n\nRunning the build setup script."
# Overriding global run_conda_forge_build_setup_osx with local copy.
source recipe/run_conda_forge_build_setup_osx


( endgroup "Configuring conda" ) 2> /dev/null

echo -e "\n\nMaking the build clobber file"
make_build_number ./ ./recipe ./.ci_support/${CONFIG}.yaml

if [[ -f LICENSE.txt ]]; then
  cp LICENSE.txt "recipe/recipe-scripts-license.txt"
fi

if [[ "${BUILD_WITH_CONDA_DEBUG:-0}" == 1 ]]; then
    if [[ "x${BUILD_OUTPUT_ID:-}" != "x" ]]; then
        EXTRA_CB_OPTIONS="${EXTRA_CB_OPTIONS:-} --output-id ${BUILD_OUTPUT_ID}"
    fi
    conda debug ./recipe -m ./.ci_support/${CONFIG}.yaml \
        ${EXTRA_CB_OPTIONS:-} \
        --clobber-file ./.ci_support/clobber_${CONFIG}.yaml

    # Drop into an interactive shell
    /bin/bash
else

    if [[ "${HOST_PLATFORM}" != "${BUILD_PLATFORM}" ]]; then
        EXTRA_CB_OPTIONS="${EXTRA_CB_OPTIONS:-} --no-test"
    fi

    conda mambabuild ./recipe -m ./.ci_support/${CONFIG}.yaml \
        --suppress-variables ${EXTRA_CB_OPTIONS:-} \
        --clobber-file ./.ci_support/clobber_${CONFIG}.yaml
    ( startgroup "Validating outputs" ) 2> /dev/null

    validate_recipe_outputs "${FEEDSTOCK_NAME}"

    ( endgroup "Validating outputs" ) 2> /dev/null

    ( startgroup "Uploading packages" ) 2> /dev/null

    if [[ "${UPLOAD_PACKAGES}" != "False" ]] && [[ "${IS_PR_BUILD}" == "False" ]]; then
      upload_package --validate --feedstock-name="${FEEDSTOCK_NAME}" ./ ./recipe ./.ci_support/${CONFIG}.yaml
    fi

    ( endgroup "Uploading packages" ) 2> /dev/null
fi