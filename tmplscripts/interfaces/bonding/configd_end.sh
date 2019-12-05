#!/opt/vyatta/bin/cliexec

# this brings the interface up too
vyatta-intf-end $VAR(@)

if [ ${COMMIT_ACTION} = 'SET' ]; then
    /opt/vyatta/sbin/vyatta-link-detect $VAR(@) on
elif [ ${COMMIT_ACTION} = 'ACTIVE' ]; then
    /opt/vyatta/sbin/vyatta-bonding --dev=$VAR(@) --mode=$VAR(./mode/@) --lacp_activity=$VAR(./lacp-options/activity/@) --lacp_key=$VAR(./lacp-options/key/@) --minimum-links=$VAR(minimum-links/@)
fi
