#!/bin/zsh

##   Audirvana Scrobbler
##   Ver: 1.1.0, May 2021
##
##   Scrobble Audirvana tracks to last.fm eith awareness of album artist
##   See README for dependencies and installation
##
##   2019-11-10

## 	 Forked February 2021 from https://github.com/sprtm/audirvana-scrobbler
##
##   Album artist support requires a companion change to lfm; see README.

###  The original audirvana-scrobbler carries no licensing information.
###  This modification is released under the terms of the MIT License.
###  No copyright is asserted over unmodified code sections.

##   Copyright (c) 2020 M. Ho, Belle Aurore Enterprises <empress*at* notthatinnocent=dot=com>

##   Permission is hereby granted, free of charge, to any person obtaining a copy
##   of this software and associated documentation files (the "Software"), to deal
##   in the Software without restriction, including without limitation the rights
##   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
##   copies of the Software, and to permit persons to whom the Software is
##   furnished to do so, subject to the following conditions:

##   The above copyright notice and this permission notice shall be included in all
##   copies or substantial portions of the Software.

##   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
##   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
##   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
##   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
##   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
##   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
##   SOFTWARE.

## Set LASTFM_USER in your shell environment. If you don't, this line will set it to "nobody".
export LASTFM_USER=${LASTFM_USER:=nobody}

## Set these environment variables in the shell to override the listed defaults.
export DEFAULT_SLEEP_TIME=${AUDIRVANA_DEFAULT_SLEEP_TIME:=10}
export LONG_SLEEP_TIME=${AUDIRVANA_LONG_SLEEP_TIME:=20}
export TERM=${TERM:=xterm-256color}
		# minimum absolute time within track, in seconds
       THRESHOLD_ABSOLUTE=${AUDIRVANA_THRESHOLD_ABSOLUTE:=120}
# minimum percentage position within track
export THRESHOLD_PCT=${AUDIRVANA_THRESHOLD_PCT:=40}

## External transfer variables
export AUDIRVANA_RUNNING_STATE

## Status variables
export AUDIRVANA_IDLE_THRESHOLD=$(( 300 / DEFAULT_SLEEP_TIME ))
export AUDIRVANA_IDLE_TIME=0
export CURRENT_ALBUM=""
       CURRENT_ALBUM_ARTIST=""
export CURRENT_ARTIST=""
export CURRENT_PLAYER_STATE
export CURRENT_POSITION=""
export CURRENT_TRACK=""
       CURRENT_URL=""
       NOW_PLAYING_TRACK_DATA=""
       PREVIOUS_URL=""
export SCROBBLE_MESSAGE="Nothing to scrobble."
export SLEEP_TIME="$DEFAULT_SLEEP_TIME"
export TIMESTAMP=""
export TRACK_DURATION=""
export TRACK_HAS_BEEN_SCROBBLED=false
export VERSION="1.0.1-aa-0.2"

# functions
function IS_AUDIRVANA_RUNNING {
	AUDIRVANA_RUNNING_STATE=$(osascript <<-APPLESCRIPT
		tell application "System Events"
			set listApplicationProcessNames to name of every application process
			if listApplicationProcessNames contains "Audirvana" then
				set AUDIRVANA_RUNNING_STATE to "yes"
			else
				set AUDIRVANA_RUNNING_STATE to "no"
			end if
		end tell
	APPLESCRIPT
	)
}

function CHECK_AUDIRVANA_STATE {
	CURRENT_PLAYER_STATE=$(osascript -e 'tell application "Audirvana" to get player state')
}

function GET_NOW_PLAYING_DATA {
    oldifs=$IFS
    IFS=$'\n'
	NOW_PLAYING_TRACK_DATA=($(osascript <<-APPLESCRIPT
	tell application "Audirvana"
		set playingTrack to playing track title
		set playingAlbum to playing track album
		set playingArtist to playing track artist
		set playingDuration to playing track duration
		set playingPosition to player position
		set playingURL to playing track url
	end tell

	set myList to {playingTrack, playingAlbum, playingArtist, playingDuration, playingPosition, playingURL}
	set myString to "" as text
	repeat with myItem in myList
		set myString to myString & myItem & linefeed
	end repeat
	return myString
	APPLESCRIPT
))
    IFS=$oldifs

    CURRENT_TRACK=$NOW_PLAYING_TRACK_DATA[1]
    CURRENT_ALBUM=$NOW_PLAYING_TRACK_DATA[2]
    CURRENT_ARTIST=$NOW_PLAYING_TRACK_DATA[3]
    TRACK_DURATION=$NOW_PLAYING_TRACK_DATA[4]

    # ghetto cast to int
    integer position
    position=$NOW_PLAYING_TRACK_DATA[5]
    CURRENT_POSITION=$position

    # add missing slash after file://
    CURRENT_URL=${NOW_PLAYING_TRACK_DATA[6]/#file:\/\//file:\/\/\/}

    TRACK_THRESHOLD=$(( TRACK_DURATION*THRESHOLD_PCT/100 ))
}

function TEST_IF_TRACK_IS_ABOVE_THRESHOLD {
	if [[ -n "$TIMESTAMP" && ${CURRENT_POSITION} -gt $TRACK_THRESHOLD && $CURRENT_POSITION -gt $THRESHOLD_ABSOLUTE && $TRACK_HAS_BEEN_SCROBBLED = false ]]; then
		SCROBBLE
	fi
}

function ECHO_FUNCTION {
	echo -n "\e[0J" # clear everything after the cursor
	echo "\r\e[0K  Audirvana....: $1\n  Last.fm......: $SCROBBLE_MESSAGE"
	tput cup 4
}

function COMPARE_TRACK_DATA {
	if [[ "$CURRENT_URL" != "$PREVIOUS_URL" ]]; then
		CURRENT_ALBUM_ARTIST=""
		if [[ $CURRENT_URL =~ ^file: ]]; then
			album_artist=$(mediainfo "$CURRENT_URL" | fgrep 'Album/Performer ' | sed -E -e 's/^[^:]+: //')
			if [[ -n "$album_artist" && "$album_artist" != "$CURRENT_ARTIST" ]]; then
				CURRENT_ALBUM_ARTIST="$album_artist"
			fi
		fi
		TRACK_HAS_BEEN_SCROBBLED=false
		TIMESTAMP=$(date "+%Y-%m-%d.%H:%M")
		NOW_PLAYING
	fi
	PREVIOUS_URL="$CURRENT_URL"
}

function NOW_PLAYING {
	SCROBBLE_MESSAGE=$(scrobbler now-playing "$LASTFM_USER" "$CURRENT_ARTIST" "$CURRENT_TRACK" -a "$CURRENT_ALBUM" -d "$TRACK_DURATION"s)
	SCROBBLE_MESSAGE="$SCROBBLE_MESSAGE:u"
	SCROBBLE_MESSAGE="$(tput setaf 2)[${SCROBBLE_MESSAGE%?}] $(tput sgr 0)${CURRENT_TRACK} — ${CURRENT_ARTIST}"
}

function SCROBBLE {
	if [[ -n "$CURRENT_ALBUM_ARTIST" ]]; then
		SCROBBLE_MESSAGE=$(scrobbler scrobble "$LASTFM_USER" "$CURRENT_ARTIST" "$CURRENT_TRACK" "$TIMESTAMP" -a "$CURRENT_ALBUM" --album-artist="$CURRENT_ALBUM_ARTIST" -d "$TRACK_DURATION"s)
		SCROBBLE_MESSAGE="${${SCROBBLE_MESSAGE:u}%?} (with album artist)"
	else
	SCROBBLE_MESSAGE=$(scrobbler scrobble "$LASTFM_USER" "$CURRENT_ARTIST" "$CURRENT_TRACK" "$TIMESTAMP" -a "$CURRENT_ALBUM" -d "$TRACK_DURATION"s)
		SCROBBLE_MESSAGE=${${SCROBBLE_MESSAGE:u}%?}
	fi
	SCROBBLE_MESSAGE="$(tput setaf 2)[$SCROBBLE_MESSAGE] $(tput sgr 0)$CURRENT_TRACK — $CURRENT_ARTIST"
	TRACK_HAS_BEEN_SCROBBLED=true
}


# initiate script
clear
printf "\n  Audirvana Scrobbler Script %s * Running...\n  =============================================\n\n" "$VERSION"

while true; do
	if (( AUDIRVANA_IDLE_TIME >= AUDIRVANA_IDLE_THRESHOLD )); then
		SLEEP_TIME="$LONG_SLEEP_TIME"
	fi
	IS_AUDIRVANA_RUNNING
	if [ "$AUDIRVANA_RUNNING_STATE" = no ]; then
		ECHO_FUNCTION "Application is not running."
		AUDIRVANA_IDLE_TIME=$(( AUDIRVANA_IDLE_TIME + 1))
	elif [ "$AUDIRVANA_RUNNING_STATE" = yes ]; then
		CHECK_AUDIRVANA_STATE
		if [ "$CURRENT_PLAYER_STATE" = "Playing" ]; then
			AUDIRVANA_IDLE_TIME=0
			SLEEP_TIME="$DEFAULT_SLEEP_TIME"
			GET_NOW_PLAYING_DATA
			TEST_IF_TRACK_IS_ABOVE_THRESHOLD
			ECHO_FUNCTION "$(tput setaf 3)♫ ${CURRENT_TRACK} — ${CURRENT_ARTIST} • ${CURRENT_ALBUM} ${CURRENT_ALBUM_ARTIST:+($CURRENT_ALBUM_ARTIST)} $(tput sgr 0)"
			COMPARE_TRACK_DATA
		elif [ "$CURRENT_PLAYER_STATE" = "Paused" ] || [ "$CURRENT_PLAYER_STATE" = "Stopped" ]; then
			ECHO_FUNCTION "Player is stopped/paused."
			AUDIRVANA_IDLE_TIME=$(( AUDIRVANA_IDLE_TIME + 1))
		fi
	fi
	sleep $SLEEP_TIME
done
