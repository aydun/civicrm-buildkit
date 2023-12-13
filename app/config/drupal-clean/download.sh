#!/usr/bin/env bash

## download.sh -- Download Drupal and CiviCRM

###############################################################################

git_cache_setup_id civicrm/civicrm-drupal

###############################################################################

[ -z "$CMS_VERSION" ] && CMS_VERSION=7

drupal_download

pushd "$WEB_ROOT/web"
  drush dl -y libraries-1.0 views-3.7
  drupal7_po_download "${CIVICRM_LOCALES:-de_DE}" drupal-7.x views-7.x-3.x

  pushd sites/all/modules
    git clone "${CACHE_DIR}/civicrm/civicrm-core.git"                        -b "$CIVI_VERSION"      civicrm
    git clone "${CACHE_DIR}/civicrm/civicrm-drupal.git"                      -b "7.x-$CIVI_VERSION"  civicrm/drupal
    git clone "${CACHE_DIR}/civicrm/civicrm-packages.git"                    -b "$CIVI_VERSION"      civicrm/packages
    api4_download_conditional civicrm                                                                civicrm/ext/api4

    extract-url --cache-ttl 172800 civicrm=http://download.civicrm.org/civicrm-l10n-core/archives/civicrm-l10n-daily.tar.gz
    ## or https://raw.github.com/civicrm/l10n/master/po/fr_CA/civicrm.mo => civicrm/l10n/fr_CA/LC_MESSAGES/
    pushd civicrm
      composer install
    popd
  popd

popd
