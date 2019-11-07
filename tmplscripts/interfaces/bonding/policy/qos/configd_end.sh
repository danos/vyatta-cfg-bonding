#!/opt/vyatta/bin/cliexec

if [ ${COMMIT_ACTION} != 'DELETE' ] ; then
	/opt/vyatta/sbin/qos-commit.pl --update-binding $VAR(@)
fi
