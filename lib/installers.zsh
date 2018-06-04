#!/usr/bin/env zsh
libdir=${0:a:h}
source $libdir/dotfiles.zsh
source $libdir/terminal.zsh
source $libdir/homebrew.zsh
source $libdir/mas.zsh
source $libdir/git.zsh

function link_files() {
  case "$1" in
    link )
      link_file $2 $3
      ;;
    copy )
      copy_file $2 $3
      ;;
    git )
      git_clone $2 $3
      ;;
    * )
      fail "Unknown link type: $1"
      ;;
  esac
}

function link_file() {
  ln -s -f $1 $2
  success "linked $1 to $2"
}

function copy_file() {
  cp $1 $2
  success "copied $1 to $2"
}

function open_file() {
  run "opening $1" "open $1"
  success "opened $1"
}

function install_file() {
  file_type=$1
  file_source=$2
  file_dest=$3
  if [ -f $file_dest ] || [ -d $file_dest ]; then
    overwrite=false
    backup=false
    skip=false

    if [ "$overwrite_all" = "false" ] && [ "$backup_all" = "false" ] && [ "$skip_all" = "false" ] && [ "$skip_all_silent" = "false" ]; then
      user "File already exists: `basename $file_dest`, what do you want to do? [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
      read -r action

      case "$action" in
        o )
          overwrite=true;;
        O )
          overwrite_all=true;;
        b )
          backup=true;;
        B )
          backup_all=true;;
        s )
          skip=true;;
        S )
          skip_all=true;;
        * )
          ;;
      esac
    fi

    if [ "$overwrite" = "true" ] || [ "$overwrite_all" = "true" ]; then
      rm -rf $file_dest
      success "removed $file_dest"
      link_files $file_type $file_source $file_dest
    fi

    if [ "$backup" = "true" ] || [ "$backup_all" = "true" ]; then
      mv $file_dest $file_dest\.backup
      success "moved $file_dest to $file_dest.backup"
    fi

    if [ "$skip" = "false" ] && [ "$skip_all" = "false" ] && [ "$skip_all_silent" = "false" ]; then
      link_files $file_type $file_source $file_dest
    elif [ "$skip_all_silent" = "false" ]; then
      success "skipped $file_source"
    fi

  else
    link_files $file_type $file_source $file_dest
  fi
}

function run_installers() {
  info 'running installers'
  dotfiles_find install.sh | while read installer ; do run "running ${installer}" "${installer}" ; done

  info 'opening files'
  for file_source in $(dotfiles_find install.open); do
    OLD_IFS=$IFS
    IFS=$'\n'
    basedir="$(dirname $file_source)"
    for file in `cat $file_source`; do
      canonical_file="$basedir/$file"
      open_file "$canonical_file"
    done
    IFS=$OLD_IFS
  done
}

function run_postinstall() {
  dotfiles_find post-install.sh | while read installer ; do run "running ${installer}" "${installer}" ; done
}

function create_localrc() {
  LOCALRC=$HOME/.localrc
  if [ ! -f "$LOCALRC" ]; then
    echo "DEFAULT_USER=$USER" > $LOCALRC
    success "created $LOCALRC"
  fi
}

function dotfiles_install() {
  overwrite_all=false
  backup_all=false
  skip_all=false

  # git repositories
  for file_source in $(dotfiles_find \*.gitrepo); do
    file_dest="$HOME/.`basename \"${file_source%.*}\"`"
    install_file git $file_source $file_dest
  done

  # repeat git repositories, skipping existing and suppressing logging so we pickup dotfiles added by the previous step
  skip_all_silent_prev="$skip_all_silent"
  skip_all_silent=true
  for file_source in $(dotfiles_find \*.gitrepo); do
    file_dest="$HOME/.`basename \"${file_source%.*}\"`"
    install_file git $file_source $file_dest
  done
  skip_all_silent="$skip_all_silent"

  # symlinks
  for file_source in $(dotfiles_find \*.symlink); do
    file_dest="$HOME/.`basename \"${file_source%.*}\"`"
    install_file link $file_source $file_dest
  done

  # preferences
  for file_source in $(dotfiles_find \*.plist); do
    file_dest="$HOME/Library/Preferences/`basename $file_source`"
    install_file copy $file_source $file_dest
  done

  # fonts
  for file_source in $(dotfiles_find \*.otf -or -name \*.ttf -or -name \*.ttc); do
    file_dest="$HOME/Library/Fonts/$(basename $file_source)"
    install_file copy $file_source $file_dest
  done

  # launch agents
  for file_source in $(dotfiles_find \*.launchagent); do
    file_dest="$HOME/Library/LaunchAgents/$(basename $file_source | sed 's/.launchagent//')"
    install_file copy $file_source $file_dest
  done
}

function install() {
    dotfiles_install
    run_installers

    # Update brew and pull git repositories concurrently
    brew_update &
    git_pull_repos
    wait

    # Install/upgrade
    brew_upgrade_formulas
    brew_install_formulas
    mas_upgrade_formulas
    mas_install_formulas

    # Post-install
    run_postinstall
    create_localrc
}

function main() {
  skip_all_silent=false
  if [ "$1" = "update" ]; then
    info 'updating dotfiles'
    skip_all_silent=true
    install
    info 'complete! restart your session for environment changes to take effect'
  else
    info 'installing dotfiles'
    install
    info 'complete! use dotfiles_update to keep up to date. restart your session for environment changes to take effect'
  fi

  echo ''
}

main "$@"
