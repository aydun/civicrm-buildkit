#!/usr/bin/env bash

## download.sh -- Download Backdrop and CiviCRM

###############################################################################

[ -z "$CMS_VERSION" ] && CMS_VERSION="1.27.x" ## FIXME: After 1.28-dev stabilizes, we can switch back to 1.x.
[ -z "$CIVI_VERSION" ] && CIVI_VERSION=master

backdrop_download
pushd "$WEB_ROOT/web" >> /dev/null
  BACKDROP_LANG_VER=$( [ "$CMS_VERSION" = "1.x" ] && _drupalx_version x.y-1 || _drupalx_version x.y )
  backdrop_po_download "${CIVICRM_LOCALES:-de_DE}" "backdropcms-${BACKDROP_LANG_VER}"
popd >> /dev/null

echo "[[Download CiviCRM]]"
[ ! -d "$WEB_ROOT/web/modules" ] && mkdir -p "$WEB_ROOT/web/modules"
pushd "$WEB_ROOT/web/modules" >> /dev/null

  git_cache_clone civicrm/civicrm-core      -b "$CIVI_VERSION"     civicrm
  git_cache_clone civicrm/civicrm-backdrop  -b "1.x-$CIVI_VERSION" civicrm/backdrop
  git_cache_clone civicrm/civicrm-packages  -b "$CIVI_VERSION"     civicrm/packages

  civicrm_l10n_setup civicrm

  git_set_hooks civicrm-drupal      civicrm/backdrop   "../tools/scripts/git"
  git_set_hooks civicrm-core        civicrm            "tools/scripts/git"
  git_set_hooks civicrm-packages    civicrm/packages   "../tools/scripts/git"

popd >> /dev/null
