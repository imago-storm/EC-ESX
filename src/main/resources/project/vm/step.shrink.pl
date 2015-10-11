#
#  Copyright 2015 Electric Cloud, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

use ElectricCommander;
use ElectricCommander::PropDB;
use strict;

$::ec = new ElectricCommander();
$::ec->abortOnError(0);
$::pdb = new ElectricCommander::PropDB($::ec);

$| = 1;

my $esx_config  = "$[connection_config]";
my $deployments = '$[deployments]';

my $opts;
$opts->{connection_config} = q{$[connection_config]};
$[/myProject/procedure_helpers/preamble]





sub main {
    print "ESX Shrink:\n";

    # Validate inputs
    $esx_config =~ s/[^A-Za-z0-9_-]//gixms;

    # unpack request
    my $xPath = XML::XPath->new(xml => $deployments);
    my $nodeset = $xPath->find('//Deployment');

    # put request in perl hash
    # if this is the first time CM has asked to terminate, the state will be alive
    # if the request was tendered once before but the resource was in use at the time, the
    # state will be pending
    my $deplist;
    foreach my $node ($nodeset->get_nodelist) {

        # for each deployment
        my $input_handle = $xPath->findvalue('handle',    $node)->string_value;
        my $hostname     = $xPath->findvalue('hostname',  $node)->string_value;
        my $res          = $xPath->findvalue('resource',  $node)->string_value;
        my $ipaddress    = $xPath->findvalue('ipaddress', $node)->string_value;
        my $resultspath  = $xPath->findvalue('results',   $node)->string_value;
        my $state        = $xPath->findvalue('state',     $node)->string_value;    # alive | pending

        print "Input: $input_handle state=$state resource=$res\n";
        $deplist->{$input_handle}{hostname}    = $hostname;
        $deplist->{$input_handle}{resource}    = $res;
        $deplist->{$input_handle}{ipaddress}   = $ipaddress;
        $deplist->{$input_handle}{resultspath} = $resultspath;
        $deplist->{$input_handle}{state}       = $state;
        $deplist->{$input_handle}{result}      = "";
        $deplist->{$input_handle}{mesg}        = "";
        $deplist->{$input_handle}{inuse}       = "yes";
    }

    # for each candidate that is alive, remove it
    # from any pools and move to pending state
    foreach my $handle (keys %{$deplist}) {
        if ($deplist->{$handle}{state} eq "alive") {

            # Remove resource from any pool
            $deplist->{$handle}{state} = "pending";
            my $worked = removeFromPools($deplist->{$handle}{resource});
            if ($worked ne "") {
                $deplist->{$handle}{result} = "error";
                $deplist->{$handle}{mesg}   = $worked;
            }
        }
    }

    ## at this point every item in deplist should have state
    ## pending. Figure out if the resource is in use
    determineResourcesInUse($deplist);

    ## try to delete resources that are not in use
    my $err = deleteVMs($deplist);
    if ($err ne "") {
        print "error: $err\n";
    }

    my $xmlout = "";
    addXML(\$xmlout, "<ShrinkResponse>");
    foreach my $handle (keys %{$deplist}) {
        my $result = $deplist->{$handle}{result};
        my $mesg   = $deplist->{$handle}{mesg};

        # if something drastic happened, report back errors for all actions
        if ($err ne "") {
            $result = "error";
            $mesg   = $err;
        }
        addXML(\$xmlout, "<Deployment>");
        addXML(\$xmlout, "  <handle>$handle</handle>");
        addXML(\$xmlout, "  <result>$result</result>");
        addXML(\$xmlout, "  <message>$mesg</message>");
        addXML(\$xmlout, "</Deployment>");
    }
    addXML(\$xmlout, "</ShrinkResponse>");
    $::ec->setProperty("/myJob/CloudManager/shrink", $xmlout);
    print "\n$xmlout\n";
    exit 0;
}

#####################################
# removefrompools
#
# remove the resource from all pools
#####################################
sub removeFromPools {
    my ($resource) = @_;

    print "Remove from pools: $resource\n";
    my $xpath = $::ec->modifyResource($resource, { pools => "" });
    if ($xpath) {
        my $code = $xpath->findvalue('//code')->string_value;
        if ($code ne "") {
            my $mesg = $xpath->findvalue('//message')->string_value;
            print "modifyResource returned code is '$code'\n$mesg\n";
            return $mesg;
        }
    }
    return "";
}

######################################
# get current usage for all resources
#
######################################
# sample returns
#
## getresource <resource>
##  <response requestid="1">
##      <resource>
##        <resourceid>115</resourceid>
##        <resourcename>poof3</resourcename>
##        <agentstate>
##          <alive>1</alive>
##          <details>the agent is alive</details>
##          <message>the agent is alive</message>
##          <pingtoken>1311365796</pingtoken>
##          <protocolversion>5</protocolversion>
##          <state>alive</state>
##          <time>2011-07-24t03:37:52.407z</time>
##          <version>3.10.0.41449</version>
##        </agentstate>
##        <createtime>2011-07-18t05:40:15.978z</createtime>
##        <description />
##        <exclusivejobname>job_5057_201107232051</exclusivejobname>
##        <hostname>localhost</hostname>
##        <lastmodifiedby>project: test</lastmodifiedby>
##        <lastruntime>2011-07-24t03:51:14.549z</lastruntime>
##        <modifytime>2011-07-24t03:51:14.549z</modifytime>
##        <owner>admin</owner>
##        <port />
##        <proxyport />
##        <resourcedisabled>0</resourcedisabled>
##        <shell />
##        <stepcount>0</stepcount>
##        <steplimit>1</steplimit>
##        <usessl>1</usessl>
##        <workspacename />
##        <exclusivejobid>5057</exclusivejobid>
##        <propertysheetid>85891</propertysheetid>
##        <pools>cloudtest</pools>
##      </resource>
##    </response>
##
## getresourceusage
##  <response requestid="1">
##      <resourceusage>
##        <resourceusageid>49</resourceusageid>
##        <jobname>job_5058_201107232053</jobname>
##        <jobstepname>use resource</jobstepname>
##        <resourcename>poof2</resourcename>
##        <jobid>5058</jobid>
##        <jobstepid>39863</jobstepid>
##        <resourceid>114</resourceid>
##      </resourceusage>
##    </response>
##
##

sub determineResourcesInUse {
    my ($deplist) = @_;

    ## first check if any resources specified in the input list
    ## if not, don't bother checking for usage
    my $resourceSpecified = 0;
    foreach my $handle (keys %{$deplist}) {
        my $resource = $deplist->{$handle}{resource};

        # mark as not in use/pending so it will be considered
        # for immediate delete
        if ($resource eq "") {
            $deplist->{$handle}{inuse} = "no";
            $deplist->{$handle}{result} = "pending";
        } else {
            $resourceSpecified = 1;
        }
    }
    if (! $resourceSpecified) { 
        print "No resources specified, skipping usage checks\n";
        return;
    }
    
    ## get resource usage for all resources
    my $xpath = $::ec->getResourceUsage();
    my $usage;

    ##  put into perl hash
    my $nodeset = $xpath->find('//resourceUsage');
    foreach my $node ($nodeset->get_nodelist) {
        my $r = $xpath->findvalue('resourceName', $node)->string_value;
        my $j = $xpath->findvalue('jobName',      $node)->string_value;
        $usage->{$r} = $j;
        print "Resource $r in use by job $j\n";
    }

    foreach my $handle (keys %{$deplist}) {
        my $state    = $deplist->{$handle}{state};
        my $resource = $deplist->{$handle}{resource};
        if ("$resource" eq "") {
            next;
        }
        
        print "\nCheck pending resources $resource in state $state\n";

        # if resource not exclusively allocated
        if ($usage->{$resource} eq "") {

            # not exclusive, see if it is in use
            my $path = $::ec->getResource($resource);
            my $job  = $path->findvalue("//exclusiveJobName")->string_value;
            if ($job ne "") {
                print "resource $resource is exclusive to job $job\n";
                $deplist->{$handle}{inuse}  = "yes";
                $deplist->{$handle}{result} = "pending";
                next;
            }
        }
        else {
            print "resource $resource is used by job " . $usage->{$resource} . "\n";
            $deplist->{$handle}{inuse}  = "yes";
            $deplist->{$handle}{result} = "pending";
            next;
        }
        ## if not exclusive or individual usage, mark as ready for termination
        print "resource $resource is not in use\n";
        $deplist->{$handle}{inuse} = "no";
    }
}

######################################################
# Delete vms
#  returns "" on success
#          error string on failure
######################################################
sub deleteVMs {
    my ($deplist) = @_;

    # One Cleanup request will be made for each one
    my $vm = "";
    my $mesg = "";
    
    my $proj = "$[/myProject/projectName]";
    my $proc = "PowerOff";

    ### for all pending and not in use , add to list for delete
    foreach my $handle (keys %{$deplist}) {
        if (   $deplist->{$handle}{state} ne "pending"
            || $deplist->{$handle}{inuse} eq "yes")
        {
            next;
        }
        $vm = $handle;       
        
        

        ### delete vms ###
        print("Running ESX PowerOff\n");
        print "  vm:$handle\n";
        print "  hostname:$deplist->{$handle}{hostname}\n";
        print "  resource:$deplist->{$handle}{resource}\n";
        print "  ipaddress:$deplist->{$handle}{ipaddress}\n";

        my $xPath = $::ec->runProcedure(
            "$proj",
            {
               procedureName   => "$proc",
               pollInterval    => 1,
               timeout         => 3600,
               actualParameter => [

                                                               { actualParameterName => "connection_config", value => "$esx_config" },
                                                               { actualParameterName => "esx_vmname",        value => "$handle" },
                                  ],
            }
        );
        if ($xPath) {
            my $code = $xPath->findvalue('//code')->string_value;
            if ($code ne "") {
                $mesg = $xPath->findvalue('//message')->string_value;
                print "Run procedure returned code is '$code'\n$mesg\n";
            }
        }
        
        
        

        my $outcome = $xPath->findvalue('//outcome')->string_value;
        my $jobid   = $xPath->findvalue('//jobId')->string_value;
        if (!$jobid) {

            # at this point we have to assume all shrinks failed because we have no
            # data otherwise
            return "error", "could not find jobid of PowerOff job. " . $xPath->findvalue('//message')->string_value;
        }
        
        print "outcome: " . $outcome . "\n";

        my $state = $gt->checkState($handle);       
        my $err = "success";
        my $msg = "";
        
        
        if ("$state" ne "poweredOff") {
            print("VM $handle still running\n");
            $deplist->{$handle}{state}  = "pending";
            $deplist->{$handle}{result} = "error";
            $deplist->{$handle}{mesg}   = "VM still running";
        } else {
            print("VM $handle stopped\n");
            #-------------------------------------
            # Delete resources (if created)
            #-------------------------------------

            print "Deleting resource $deplist->{$handle}{resource} \n";
            my $cmdrresult = $::ec->deleteResource($deplist->{$handle}{resource});

            #-----------------------------
            # Check for error return
            #-----------------------------
            my $errMsg = $::ec->checkAllErrors($cmdrresult);
            if ($errMsg ne "") {
                print "Error: $errMsg";
                exit 1;

            }
            
            $deplist->{$handle}{state}  = "stopped";
            $deplist->{$handle}{result} = "success";
            $deplist->{$handle}{mesg}   = "";
        }
       

    }
    return "";

}

sub addXML {
    my ($xml, $text) = @_;
    ## TODO encode
    ## TODO autoindent
    $$xml .= $text;
    $$xml .= "\n";
}

main();
