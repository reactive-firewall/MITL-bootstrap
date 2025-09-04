#!/usr/bin/env bash
#
# Disclaimer of Warranties.
# A. YOU EXPRESSLY ACKNOWLEDGE AND AGREE THAT, TO THE EXTENT PERMITTED BY
#    APPLICABLE LAW, USE OF THIS SHELL SCRIPT AND ANY SERVICES PERFORMED
#    BY OR ACCESSED THROUGH THIS SHELL SCRIPT IS AT YOUR SOLE RISK AND
#    THAT THE ENTIRE RISK AS TO SATISFACTORY QUALITY, PERFORMANCE, ACCURACY AND
#    EFFORT IS WITH YOU.
#
# B. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THIS SHELL SCRIPT
#    AND SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE", WITH ALL FAULTS AND
#    WITHOUT WARRANTY OF ANY KIND, AND THE AUTHOR OF THIS SHELL SCRIPT'S LICENSORS
#    (COLLECTIVELY REFERRED TO AS "THE AUTHOR" FOR THE PURPOSES OF THIS DISCLAIMER)
#    HEREBY DISCLAIM ALL WARRANTIES AND CONDITIONS WITH RESPECT TO THIS SHELL SCRIPT
#    SOFTWARE AND SERVICES, EITHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT
#    NOT LIMITED TO, THE IMPLIED WARRANTIES AND/OR CONDITIONS OF
#    MERCHANTABILITY, SATISFACTORY QUALITY, FITNESS FOR A PARTICULAR PURPOSE,
#    ACCURACY, QUIET ENJOYMENT, AND NON-INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# C. THE AUTHOR DOES NOT WARRANT AGAINST INTERFERENCE WITH YOUR ENJOYMENT OF THE
#    THE AUTHOR's SOFTWARE AND SERVICES, THAT THE FUNCTIONS CONTAINED IN, OR
#    SERVICES PERFORMED OR PROVIDED BY, THIS SHELL SCRIPT WILL MEET YOUR
#    REQUIREMENTS, THAT THE OPERATION OF THIS SHELL SCRIPT OR SERVICES WILL
#    BE UNINTERRUPTED OR ERROR-FREE, THAT ANY SERVICES WILL CONTINUE TO BE MADE
#    AVAILABLE, THAT THIS SHELL SCRIPT OR SERVICES WILL BE COMPATIBLE OR
#    WORK WITH ANY THIRD PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES,
#    OR THAT DEFECTS IN THIS SHELL SCRIPT OR SERVICES WILL BE CORRECTED.
#    INSTALLATION OF THIS THE AUTHOR SOFTWARE MAY AFFECT THE USABILITY OF THIRD
#    PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES.
#
# D. YOU FURTHER ACKNOWLEDGE THAT THIS SHELL SCRIPT AND SERVICES ARE NOT
#    INTENDED OR SUITABLE FOR USE IN SITUATIONS OR ENVIRONMENTS WHERE THE FAILURE
#    OR TIME DELAYS OF, OR ERRORS OR INACCURACIES IN, THE CONTENT, DATA OR
#    INFORMATION PROVIDED BY THIS SHELL SCRIPT OR SERVICES COULD LEAD TO
#    DEATH, PERSONAL INJURY, OR SEVERE PHYSICAL OR ENVIRONMENTAL DAMAGE,
#    INCLUDING WITHOUT LIMITATION THE OPERATION OF NUCLEAR FACILITIES, AIRCRAFT
#    NAVIGATION OR COMMUNICATION SYSTEMS, AIR TRAFFIC CONTROL, LIFE SUPPORT OR
#    WEAPONS SYSTEMS.
#
# E. NO ORAL OR WRITTEN INFORMATION OR ADVICE GIVEN BY THE AUTHOR
#    SHALL CREATE A WARRANTY. SHOULD THIS SHELL SCRIPT OR SERVICES PROVE DEFECTIVE,
#    YOU ASSUME THE ENTIRE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.
#
#    Limitation of Liability.
# F. TO THE EXTENT NOT PROHIBITED BY APPLICABLE LAW, IN NO EVENT SHALL THE AUTHOR
#    BE LIABLE FOR PERSONAL INJURY, OR ANY INCIDENTAL, SPECIAL, INDIRECT OR
#    CONSEQUENTIAL DAMAGES WHATSOEVER, INCLUDING, WITHOUT LIMITATION, DAMAGES
#    FOR LOSS OF PROFITS, CORRUPTION OR LOSS OF DATA, FAILURE TO TRANSMIT OR
#    RECEIVE ANY DATA OR INFORMATION, BUSINESS INTERRUPTION OR ANY OTHER
#    COMMERCIAL DAMAGES OR LOSSES, ARISING OUT OF OR RELATED TO YOUR USE OR
#    INABILITY TO USE THIS SHELL SCRIPT OR SERVICES OR ANY THIRD PARTY
#    SOFTWARE OR APPLICATIONS IN CONJUNCTION WITH THIS SHELL SCRIPT OR
#    SERVICES, HOWEVER CAUSED, REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT,
#    TORT OR OTHERWISE) AND EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE
#    POSSIBILITY OF SUCH DAMAGES. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION
#    OR LIMITATION OF LIABILITY FOR PERSONAL INJURY, OR OF INCIDENTAL OR
#    CONSEQUENTIAL DAMAGES, SO THIS LIMITATION MAY NOT APPLY TO YOU. In no event
#    shall THE AUTHOR's total liability to you for all damages (other than as may
#    be required by applicable law in cases involving personal injury) exceed
#    the amount of five dollars ($5.00). The foregoing limitations will apply
#    even if the above stated remedy fails of its essential purpose.
################################################################################
# PATH=${PATH:-"/bin:/sbin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"} ;

# TODO: make this able to detect host hermetically
# FreeBSD will be able to use root host
HOST_TOOLCHAIN_PATH=${HOST_TOOLCHAIN_PATH}
# MacOS/Darwin host might be different like:
# HOST_TOOLCHAIN_PATH=$(xcode-select --print-path)

# primitive stage0 make root script
PREFIX_STUB=${HOST_TOOLCHAIN_PATH}${PREFIX:-/usr}
BASH_CMD=$(which bash)
test -x "${BASH_CMD}" || exit 126 ;  # need host bash

# Get the input path of this script as called
input_path="$0"
# Remove the trailing slash if present
input_path="${input_path%/}"
# Extract the directory name
PATH_ARG="${input_path%/*}"

if [ -d "$PATH_ARG" ] && [ ":$PATH:" != *":$PATH_ARG:"* ] ; then
	PATH="${PATH:+"$PATH:"}$PATH_ARG" ;
	export PATH ;
fi

unset input_path ;
unset PATH_ARG ;

# bootstrap into host bash shell and run stuff:
#	usage:
#		$0 Cmd [args ...]
#
fn_host_do_cmd() {
	# setup
	cmd="$1"
	shift
	SUB_TOOL_RESULT=0
	OLDUMASK=$(umask)
	ACTION=${ACTION:-"run"}
	cd "$(pwd)" 2>/dev/null ; # initialize OLDPWD = PWD
	# do the work
	( "${BASH_CMD}" -c "./cmd-trebuchet.bash ${cmd} ${@}" ) || false ;
	SUB_TOOL_RESULT=$?
	wait ;
	# revert umask
	umask "$OLDUMASK" ;
	# return to start path
	test $(pwd) -ef ${OLDPWD} || cd "${OLDPWD}" 2>/dev/null ;
	# cleanup
	unset OLDUMASK 2>/dev/null ;
	unset ACTION 2>/dev/null ;
	# report back
	return ${SUB_TOOL_RESULT:-126} ;
}

export -f fn_host_do_cmd ;

for FILE in bin lib sbin tmp usr usr/bin usr/libexec usr/local usr/share var Users ; do
	fn_host_do_cmd mkdir -p "${DESTDIR}/${FILE}" ;
	fn_host_do_cmd chmod 755 "${DESTDIR}/${FILE}" || true ;
done ;

# basic sym-links
for FILE in sbin lib ; do
	fn_host_do_cmd ln -s ../../"${FILE}" "${DESTDIR}/usr/${FILE}" ;
done ;

# fn_host_do_cmd ln -s ../"Users" "${DESTDIR}/home" ;
# fn_host_do_cmd ln -s ../"mnt" "${DESTDIR}/Volumes" ;

fn_host_do_cmd rm "${HOST_TOOLCHAIN_PATH}/etc/os-release" 2>/dev/null || true ;

for FILE in dev etc init usr/lib mnt opt usr/libexec usr/local usr/share ; do
	fn_host_do_cmd mv "${HOST_TOOLCHAIN_PATH}/${FILE}" "${DESTDIR}/${FILE}" ;
done ;

fn_host_do_cmd cp -vf "${HOST_TOOLCHAIN_PATH}/usr/bin/toybox" "${DESTDIR}/usr/bin/toybox" 2>/dev/null || true ;

for FILE in "bash" "basename" "cat" "chgrp" "chmod" "chown" "cp" "date" "dirname" "find" "grep" "head" "halt" "ls" "ln" "mkdir" "mv" "printf" "rm" "sed" ; do
	fn_host_do_cmd ln -s "toybox" "${DESTDIR}/usr/bin/${FILE}" 2>/dev/null || true ;
done ;

# fn_host_do_cmd sha256sum "${DESTDIR}/${FILE}" || true ;
