#!/bin/csh
# /etc/profile.d/slacky-hidpi.csh
# Universal & Dynamic HiDPI & Wayland scaling for Slackware

if ( ! $?QT_AUTO_SCREEN_SCALE_FACTOR ) then
    setenv QT_AUTO_SCREEN_SCALE_FACTOR 1
endif

if ( ! $?QT_ENABLE_HIGHDPI_SCALING ) then
    setenv QT_ENABLE_HIGHDPI_SCALING 1
endif

if ( ! $?QT_SCALE_FACTOR_ROUNDING_POLICY ) then
    setenv QT_SCALE_FACTOR_ROUNDING_POLICY PassThrough
endif

if ( $?XDG_SESSION_TYPE ) then
    if ( "$XDG_SESSION_TYPE" == "wayland" ) then
        if ( ! $?QT_QPA_PLATFORM ) setenv QT_QPA_PLATFORM "wayland;xcb"
        if ( ! $?GDK_BACKEND ) setenv GDK_BACKEND "wayland,x11,*"
    endif
endif
