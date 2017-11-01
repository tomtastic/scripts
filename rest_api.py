# Example API Endpoints for use with rest.py
# 20171101 - TRCM - Moved definitions from main 'rest.py' script to separate module
#                 - Use logging to spew debug if requested
import time
import getopt
import urllib2
from lxml import etree as et
from StringIO import StringIO
import logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
#logging.basicConfig(filename='rest_api.log', level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
　
# Our public definitions ###################################
# !!! These are TEST API Endpoints !!!
# !!! These are TEST API Endpoints !!!
# !!! These are TEST API Endpoints !!!
# Replace api_site and api_url with proper PRODUCTION values
　
api_site = 'my_api_server.com'
　
def inqCI(appid,ciname,ciclass,flags):
    api_url = '/TestRESTfulWebService/testrest/inqCI'
    api_xmlquery  = CIInquiryRequest(appid,ciname,ciclass)
    api_xmlresponse = REST(api_site,api_url,api_xmlquery,flags)
    CI = CIInquiryResponse(api_xmlresponse)
    return CI
　
def listCI(appid,ciname,ciclass,flags):
    api_url = '/TestRESTfulWebService/testrest/listCI'
    api_xmlquery  = CIListRequest(appid,ciname,ciclass)
    api_xmlresponse = REST(api_site,api_url,api_xmlquery,flags)
    CIList = CIListResponse(api_xmlresponse)
    return CIList
############################################################
　
def XMLtoETREE(xml):
    etreexml = et.parse(StringIO(xml))
    return etreexml
　
def REST(site,url,xmlquery,flags):
    headers = {'Content-type': 'application/xml'}
    request = urllib2.Request('https://'+site+url, xmlquery, headers)
    if flags['debug']:
        logging.debug('SENT:'+xmlquery)
    try:
        response = urllib2.urlopen(request)
    except KeyboardInterrupt as exception:
        print '[!] KeyboardInterrupt: Caught ^C !'
        sys.exit(exception)
    except SocketError as exception:
        if exception.errno == errno.ECONNRESET:
            # How rude of the API server, a FIN-ACK would have been more polite
            print '[!] SocketError: Connection Reset By Peer! Have we spammed the API too hard?'
            sys.exit(exception)
        else:
            print '[!] SocketError: Socket Error!'
            sys.exit(exception)
    if response.getcode() != 200:
        print "[!] Something went wrong! HTTP Code:",response.getcode()
        sys.exit(1)
    xml = response.read()
    if flags['debug']:
        logging.debug('RECEIVED:'+xml)
    return xml
　
def CheckReplyCodeOK(replycode,replytext):
    if replycode == '0':
        #print '[+] Request processed successfully'
        return
    elif replycode == '1':
        print '[!] Un-Authorized Server request !'
        exit(1)
    elif replycode == '2':
        print '[!] This application has no access to this service !'
        exit(1)
    elif replycode == '3':
        print '[!] XML validation failed'
        exit(1)
    elif replycode == '7':
        print '[!] REST API is down for maintanence. Please try your request later'
        exit(1)
    elif replycode == '29':
        print '[!] No Data was found for this CI Name + CI Class combination'
        exit(1)
    else:
        print '[!] Unknown reply :', replytext
        exit(1)
　
def CIInquiryResponse(xml):
    # Take XML from the API, return reply as dict of dict.
    etree = XMLtoETREE(xml) # Turn the XML response into an ElementTree object
    results = {}
　
    namespace = etree.getroot().tag[1:].split("}")[0]
    ns = {'x' : namespace}
　
    replycode = etree.xpath("x:CIInquiryResponseDetail/x:Rc", namespaces=ns)[0].text
    replytext = etree.xpath("x:CIInquiryResponseDetail/x:ReplyText", namespaces=ns)[0].text
    CheckReplyCodeOK(replycode,replytext)
　
    cidetails = etree.findall(".//{{{0}}}CIInquiryResponseDetail".format(namespace))
    for ci in cidetails:
        ciname_tag        = ci.find("{{{0}}}CIName".format(namespace))
        results['CIName'] = ciname_tag.text if ciname_tag is not None else ""
        results['UUID'] = ciname_tag.attrib['UUID'] if ciname_tag is not None else ""
        ciclass_tag       = ci.find("{{{0}}}CIClass".format(namespace))
        results['CIClass'] = ciclass_tag.text if ciclass_tag is not None else ""
        status_tag        = ci.find("{{{0}}}Status".format(namespace))
        results['Status'] = status_tag.text if status_tag is not None else ""
        active_tag        = ci.find("{{{0}}}Active".format(namespace))
        results['Active'] = active_tag.text if active_tag is not None else ""
        groupown_tag        = ci.find("{{{0}}}OwningGroup".format(namespace))
        results['OwningGroup'] = groupown_tag.text if groupown_tag is not None else ""
        groupsup_tag        = ci.find("{{{0}}}SupportingGroup".format(namespace))
        results['SupportingGroup'] = groupsup_tag.text if groupsup_tag is not None else ""
        purpose_tag       = ci.find("{{{0}}}Purpose".format(namespace))
        results['Purpose'] = purpose_tag.text if purpose_tag is not None else ""
    return results
　
def CIListResponse(xml):
    # Take XML response from the API, return reply as dict of dict.
    etree = XMLtoETREE(xml) # Turn the XML response into an ElementTree object
    results = {}
　
    namespace = etree.getroot().tag[1:].split("}")[0]
    ns = {'x' : namespace}
　
    replycode = etree.xpath("x:CIListResponseDetail/x:Rc", namespaces=ns)[0].text
    replytext = etree.xpath("x:CIListResponseDetail/x:ReplyText", namespaces=ns)[0].text
    # or
    #replycode_tag = etree.find(".//{%s}Rc" % namespace).text
    #replytext_tag = etree.find(".//{%s}ReplyText" % namespace).text
    CheckReplyCodeOK(replycode,replytext)
　
    cidetails = etree.findall(".//{{{0}}}CIDetail".format(namespace))
    for ci in cidetails:
        results[ci] = {}  # Why is there auto-vivification in Python?
        ciname_tag        = ci.find("{{{0}}}CIName".format(namespace))
        results[ci]['CIName'] = ciname_tag.text if ciname_tag is not None else ""
        results[ci]['UUID'] = ciname_tag.attrib['UUID'] if ciname_tag is not None else ""
        ciclass_tag       = ci.find("{{{0}}}CIClass".format(namespace))
        results[ci]['CIClass'] = ciclass_tag.text if ciclass_tag is not None else ""
        status_tag        = ci.find("{{{0}}}Status".format(namespace))
        results[ci]['Status'] = status_tag.text if status_tag is not None else ""
        active_tag        = ci.find("{{{0}}}Active".format(namespace))
        results[ci]['Active'] = active_tag.text if active_tag is not None else ""
        cidescription_tag = ci.find("{{{0}}}CIDescription".format(namespace))
        results[ci]['CIDescription'] = cidescription_tag.text if cidescription_tag is not None else ""
        purpose_tag       = ci.find("{{{0}}}Purpose".format(namespace))
        results[ci]['Purpose'] = purpose_tag.text if purpose_tag is not None else ""
    return results
　
def CIListRequest(appid_param,ciname_param,ciclass_param):
    XML_NS        = "http://my_api_server.com/rest/CIListRequest_v1.0.xsd"
    NS_MAP        = {None: XML_NS} # The default namespace
    api_type      = 'CIListRequest'
    action_attr   = 'InquiryRequest'
    function_attr = 'CIList'
    epoch_attr    = str(int(time.time()))
    version_attr  = '1.0'
    # Create the ElementTree instance
    query = et.Element(api_type, nsmap=NS_MAP,
                    action=action_attr,
                    function=function_attr,
                    genDateTZ=epoch_attr,
                    version=version_attr)
    cilist_tree = et.ElementTree(query)
    appid = et.SubElement(query, 'ApplicationID')
    appid.text = appid_param
    detail = et.SubElement(query, 'CIListRequestDetail')
    ciname = et.SubElement(detail, 'CIName')
    ciname.text = ciname_param
    ciclass = et.SubElement(detail, 'CIClass')
    ciclass.text = ciclass_param
    # At this point, lets return the stringified element tree
    #xml = et.tostring(cilist_tree, xml_declaration=True, pretty_print=True, encoding='UTF-8')
    xml = et.tostring(cilist_tree, xml_declaration=True, encoding='UTF-8')
    return xml
　
def CIInquiryRequest(appid_param,ciname_param,ciclass_param):
    XML_NS        = "http://my_api_server.com/rest/CIInquiryRequest_v1.0.xsd"
    NS_MAP        = {None: XML_NS} # The default namespace
    api_type      = 'CIInquiryRequest'
    action_attr   = 'InquiryRequest'
    function_attr = 'CIInquiry'
    epoch_attr    = str(int(time.time()))
    version_attr  = '1.0'
    # Create an ElementTree instance
    query = et.Element(api_type, nsmap=NS_MAP,
                    action=action_attr,
                    function=function_attr,
                    genDateTZ=epoch_attr,
                    version=version_attr)
    ciinquiry_tree = et.ElementTree(query)
    appid = et.SubElement(query, 'ApplicationID')
    appid.text = appid_param
    detail = et.SubElement(query, 'CIInquiryRequestDetail')
    ciname = et.SubElement(detail, 'CIName')
    ciname.text = ciname_param
    ciclass = et.SubElement(detail, 'CIClass')
    ciclass.text = ciclass_param
    # At this point, lets return the stringified element tree
    #xml = et.tostring(ciinquiry_tree, xml_declaration=True, pretty_print=True, encoding='UTF-8')
    xml = et.tostring(ciinquiry_tree, xml_declaration=True, encoding='UTF-8')
    return xml
    
