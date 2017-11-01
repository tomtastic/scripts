#!/usr/bin/python
# Craft an XML request to send to a REST API, showing matching CIs.
#
# 20171011 - TRCM - lets learn python and lxml
# 20171017 - TRCM - migrate to Python2.6+ string '.format'ing
# 20171023 - TRCM - add errorhandling (KeyboardInterrupt, etc)
# 20171101 - TRCM - return dicts where possible
#                 - move API definitions to rest_api.py
#                 - move getopt parsing to own definition
import sys
import getopt
import rest_api as rest
import logging
　
def main():
    api_appid = 'unixrest'
    api_endpoint, ciname_arg, ciclass_arg, flags = ParseArguments(sys.argv)
　
    if api_endpoint == 'CIInquiry':
        for ciname in ciname_arg:
            do_CIInquiry(api_appid,ciname,ciclass_arg,flags)
    elif api_endpoint == 'CIList':
        for ciname in ciname_arg:
            do_CIList(api_appid,ciname,ciclass_arg,flags)
    else:
        usage()
        sys.exit(1)
　
def do_CIInquiry(appid,ciname,ciclass,flags):
        CI = rest.inqCI(appid,ciname,ciclass,flags)
        if flags['verbose']:
            print '{0},{1},{2},{3},{4},{5}'.format('CIName','CIClass','Status','Active','OwningGroup','SupportingGroup')
        print '{0!s},{1!s},{2!s},{3!s},{4!s},{5!s}'.format(CI['CIName'],CI['CIClass'],CI['Status'],CI['Active'],CI['OwningGroup'],CI['SupportingGroup'])
　
def do_CIList(appid,ciname,ciclass,flags):
        CIList = rest.listCI(appid,ciname,ciclass,flags)
        if flags['debug']:
            logging.debug('Number of matches:'+str(len(CIList)))
        if flags['verbose']:
            print '{0},{1},{2},{3},{4},{5}'.format('CIName','CIClass','Status','Active','Purpose','CIDescription')
        for ci in sorted(CIList.iterkeys(), reverse=True):
            print '{0!s},{1!s},{2!s},{3!s},{4!s},{5!s}'.format(CIList[ci]['CIName'],CIList[ci]['CIClass'],CIList[ci]['Status'],CIList[ci]['Active'],CIList[ci]['Purpose'],CIList[ci]['CIDescription'])
　
def ParseArguments(argv):
    flags = {'verbose':False,
             'debug':False}
    spec = [
        'inquiry',
        'list',
        'verbose',
        'debug',
        'class=' ]
    try:
        opts, args = getopt.getopt(argv[1:], 'ildvc:', spec)
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    if args == []:
        usage()
        sys.exit(1)
    for opt, arg in opts:
        if opt in ('-i', '--inquiry'):
            api_endpoint = 'CIInquiry'
            ciname_arg = args
        elif opt in ('-l', '--list'):
            api_endpoint = 'CIList'
            ciname_arg = args
        elif opt in ('-v', '--verbose'):
            flags['verbose'] = True
        elif opt in ('-d', '--debug'):
            flags['debug'] = True
        elif opt in ('-c', '--class'):
            ciclass_arg = arg
        elif opt in ('-h', '--help'):
            usage()
            sys.exit(1)
        else:
            usage()
            sys.exit(1)
    if ciclass_arg == '':
        print "[!] No CI Class provided (-c|--class), using 'Other Software OS'"
        ciclass_arg = 'Other Software OS'
    return (api_endpoint,ciname_arg,ciclass_arg,flags)
　
def usage():
    print "Usage: {0} [-v|--verbose] [-i|--inquiry] [-l|--list] [-c <class>] server_name".format(sys.argv[0])
    print "       -i | --inquiry      Results for just one servername"
    print "       -l | --list         All matched servernames (wildcard character '%')"
　
if __name__ == '__main__':
    main()
