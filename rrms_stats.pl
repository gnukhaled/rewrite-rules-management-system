#!/usr/bin/perl
#############################################################################
# Description: Rewrite rules statistical reporting tool.
# Parameters : See the "Usage" subroutine.
# Returns    : 0 on Success or 1 on Error.
# Author     : Khaled Ahmed: khaled.gnu@gmail.com
# License    : GPL <http://www.gnu.org/licenses/gpl.html>
#############################################################################

use strict;
use DateTime qw();
use Getopt::Long;
use List::MoreUtils qw(uniq);
use Cwd 'abs_path';
use File::Basename;
use Sys::Hostname;

our $VERSION=1.4;
our $absolute_path   = dirname(abs_path($0))."/";
our $rrms_logsdir    = $absolute_path."logs/";
our $baseDir =".";
our $logFile = $rrms_logsdir."rules.log";
our $localemail      = getlogin()."\@".hostname;
our %mail_addresses  = qw(Khaled khaled.gnu@gmail.com);
our $opt_startdate;
our $opt_enddate;
our $opt_date;
our @opt_domain;
our $opt_rule;
our $opt_ruletype;
our $opt_transtype;
our $opt_user;
our $opt_quarter;
our $opt_notify      = 0;
our $opt_report      = 0;
our $opt_help        = 0;
our $opt_version     = 0;
our $opt_rep_users   = 0;
our $opt_rep_domains = 0;
our $reportMode      = 0;
our $opt_security    = 0;
our $byDomain        = 0;
our $byTransType     = 0;
our $byRuleURI       = 0;
our $byRuleType      = 0;
our $byUser          = 0;
our $byDate          = 0;
our $btwnTwoDates    = 0;
our $transIsNew      = 0;
our $transIsUpdate   = 0;
our $transIsDelete   = 0;
our $transIsAll      = 0;
our $EmailMessage    = "";
our @SecurityList;
our @CombinedList;
our @ResultList;
our $firstDateInFile;
our $lastDateInFile;
our $currentYear = strtodate(scalar(localtime(time +0)))->year;
our $q1start = "01-01-".$currentYear;
our $q1end   = "31-03-".$currentYear;
our $q2start = "01-04-".$currentYear;
our $q2end   = "30-06-".$currentYear;
our $q3start = "01-07-".$currentYear;
our $q3end   = "30-09-".$currentYear;
our $q4start = "01-10-".$currentYear;
our $q4end   = "31-12-".$currentYear;
our @userStats;
our @domainStats;

GetOptions(
'start-date=s'    => \$opt_startdate,
'end-date=s'      => \$opt_enddate,
'date=s'          => \$opt_date,
'domain=s'        => \@opt_domain,
'rule=s'          => \$opt_rule,
'rule-type=s'     => \$opt_ruletype,
'transaction=s'   => \$opt_transtype,
'user=s'          => \$opt_user,
'security!'       => \$opt_security,
'quarter=s'       => \$opt_quarter,
'Q=s'             => \$opt_quarter,
'report!'         => \$opt_report,
'list-users!'     => \$opt_rep_users,
'list-domains!'   => \$opt_rep_domains,
'help!'           => \$opt_help,
'h!'              => \$opt_help,
'version!'        => \$opt_version,
'v!'              => \$opt_version,
'notify!'         => \$opt_notify
) or die "Incorrect usage!\n";

sub validateOptions{
    
    if ($opt_startdate && $opt_enddate){
        $btwnTwoDates = 1;
    }
    if ($opt_date){
        $byDate = 1;
    }
    if (scalar(@opt_domain)){
        $byDomain = 1;
        @opt_domain = split(/,/,join(',',@opt_domain));
    }else{
        $opt_domain[0] = ".*";
    }
    if ($opt_transtype){
        $opt_transtype =~ tr/[a-z]/[A-Z]/;
        
        if ($opt_transtype eq "NEW"){
            $transIsNew = 1;
        }elsif ($opt_transtype eq "UPDATE"){
            $transIsUpdate = 1;
        }elsif ($opt_transtype eq "DELETE"){
            $transIsDelete = 1;
        }
    }elsif (not $opt_transtype){
        $transIsAll = 1;
    }
    if ($opt_rule){
        $byRuleURI = 1;
    }else{
        $opt_rule = ".*";
    }
    if ($opt_user){
        $byUser = 1;
        $opt_user =~ s/([\w]+)/\u\L$1/g;
    }else{
        $opt_user = ".*";
    }
    if ($opt_ruletype){
        $opt_ruletype =~ tr/[A-Z]/[a-z]/;
    }else{
        $opt_ruletype = ".*";
    }
    if ($opt_startdate and not $opt_enddate){
        print STDERR "Please specify an end date\n";
        exit(1);
    }elsif ($opt_enddate and not $opt_startdate){
        print STDERR "Please specify a start date\n";
        exit(1);
    }
    if ($btwnTwoDates and $byDate){
        print STDERR "Please choose either [--start-date, --end-date] or [--date]\n";
        exit(1);
    }

if ($opt_quarter and ($opt_quarter ne "1" and $opt_quarter ne "2" and $opt_quarter ne "3" and $opt_quarter ne "4" and $opt_quarter ne "current")){
                print STDERR "Invalid quarter!\n";
                exit(1);
    }


    if ($opt_quarter and ($opt_startdate or $opt_enddate or $opt_date)){
        print STDERR "You can't search by quarter while specifying a date!\n";
        exit(1);
    }
    if ($opt_report){
        $reportMode = 1;
    }
    if (($opt_rep_users or $opt_rep_domains) and not ($reportMode)){
        print STDERR "You can't use [--list-users or --list-domains] while not in report mode [--report].\n";
        exit(1);
    }
    if ($reportMode and not ($opt_rep_users or $opt_rep_domains)){
        print STDERR "You must specify either [--list-users and/or --list-domains] while in report mode [--report].\n";
        exit(1);
    }
    if ($reportMode and $byDate){
        print STDERR "Please either specify a quarter search [--quarter # ] or a date frame [--start-date --end-date]\n";
        exit(1);
    }
    if ($opt_help){
        Usage();
    }
    if ($opt_version){
	print $VERSION."\n";
	exit(0);
    }
    if ($opt_notify and not $opt_report){
        print STDERR "You can only set the notify option in report mode [--report]\n";
        exit(1);
        
    }
}
sub datetostr{
    
    my $date = $_[0];
    my $flag = $_[1];
    my %months = (
    qw(1)  => "Jan",
    qw(2)  => "Feb",
    qw(3)  => "Mar",
    qw(4)  => "Apr",
    qw(5)  => "May",
    qw(6)  => "Jun",
    qw(7)  => "Jul",
    qw(8)  => "Aug",
    qw(9)  => "Sep",
    qw(10) => "Oct",
    qw(11) => "Nov",
    qw(12) => "Dec"
    );
    
    my $day    = $date->day;
    my $month  = $date->month;
    my $hour   = $date->hour;
    my $minut  = $date->minute;
    my $second = $date->second;
    my $year   = $date->year;
    
    if ($flag eq "base"){
        return $day."\/".$months{$month}."\/".$year;        
    }else{
        return $day."\/".$months{$month}."\/".$year." ".$hour.":".$minut.":".$second;
    }
}
sub strtodate{
    
    my $str = shift;
    my %months = (
    Jan => "01",
    Feb => "02" ,
    Mar => "03",
    Apr => "04",
    May => "05",
    Jun => "06",
    Jul => "07",
    Aug => "08",
    Sep => "09",
    Oct => "10",
    Nov => "11",
    Dec => "12"
    );
    
    my ($wkday,$month,$day,$hour,$minut,$second,$year) = $str =~ /^(...)\s(...)\s+([0-9]?[0-9])\s([0-9]{2}):([0-9]{2}):([0-9]{2})\s([0-9]{4})/ or die;
    my $dt = DateTime->new(
    year      => $year,
    month     => $months{$month},
    day       => $day,
    hour      => $hour,
    minute    => $minut,
    second    => $second,
    time_zone => 'local',
    );
    
    return $dt;
}
sub strtodate2{
    
    my $flag = $_[0];
    my $str  = $_[1];
    my $dt;
    my ($day,$month,$year) = $str =~ /([0-9]{2})\-([0-9]{2})\-([0-9]{4})/ or die;
    
    if ($flag eq "s"){
        $dt = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day,
        hour      => "00",
        minute    => "00",
        second    => "00",
        time_zone => 'local',
        );
    }elsif($flag eq "e"){
        $dt = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day,
        hour      => "23",
        minute    => "59",
        second    => "59",
        time_zone => 'local',
        );
    }
    return $dt;
}
sub parselog{
    
    my @AllLines;
    my $startEntry               = 0;
    my $endEntry                 = 0;
    my $startSecurityEntry       = 0;
    my $allcounter               = 0;
    my $newcounter               = 0;
    my $updatecounter            = 0;
    my $deletecounter            = 0;
    my $vanitycounter            = 0;
    my $redirectcounter          = 0;
    my $securitycounter          = 0;
    my $isNewEntry               = 0;
    my $isUpdateEntry            = 0;
    my $isDeleteEntry            = 0;
    my $isSecurityEntry          = 0;
    my $repusernewcounter        = 0;
    my $repuserupdatecounter     = 0;
    my $repuserdeletecounter     = 0;
    my $repuservanitycounter     = 0;
    my $repuserredirectcounter   = 0;
    my $repdomainnewcounter      = 0;
    my $repdomainupdatecounter   = 0;
    my $repdomaindeletecounter   = 0;
    my $repdomainvanitycounter   = 0;
    my $repdomainredirectcounter = 0;
    my $domain;
    my $transType;
    my $fromURI;
    my $toURI;
    my $ruleType;
    my $modrewopts;
    my $old_dest;
    my $user;
    my $strtimestamp;
    my $secDomains;
    my $attemptedUser;
    my $domain_bak;
    my $firstEntryDate;
    my $lastEntryDate;
    my $srchDate;
    my @uniqUsers;
    my @uniqDomains;
    my $repnewcount;
    my $repupdatecount;
    my $repdeletecount;
    my $repvanitycount;
    my $repredirectcount;
    
    open (LOGFILE,$logFile) or die "Error opening log file ".$logFile." for reading: $!";
    my $logfilesize  = -s $logFile;
    my $logfileexist = -e $logFile;
   
    if ($logfilesize > 0){
        @AllLines = <LOGFILE>;
    }else{
        print STDERR "Log file: ".$logFile." is blank\n";
        exit(1);
    }
    close LOGFILE;
    
    foreach my $line (@AllLines){
        
        if ( $line =~ /START\sRULE/){
            $startEntry = 1;
            $allcounter++;
        }elsif ($line =~ /Domain:\s(.*)/){
            $domain = $1;
            $domain_bak = $domain;
        }elsif ($line =~ /Transaction\stype:\s(.*)/){
            $transType = $1;
            if ($transType eq "UPDATE"){
                $updatecounter++;
                $isUpdateEntry = 1;
            }elsif($transType eq "NEW"){
                $newcounter++;
                $isNewEntry = 1;
            }elsif($transType eq "DELETE"){
                $deletecounter++;
                $isDeleteEntry = 1;
            }
        }elsif ($line =~ /From:\s(.*)/ and $startEntry){
            $fromURI = $1;
        }elsif ($line =~ /Rule:\s(.*)/){
            $fromURI = $1;
        }elsif ($line =~ /To:\s(.*)/ and $startEntry){
            $toURI = $1;
        }elsif ($line =~ /Rule\sType:\s(.*)/ and $startEntry){
            $ruleType = $1;
            if ($ruleType eq "redirect"){
                $redirectcounter++;
            }elsif ($ruleType eq "vanity"){
                $vanitycounter++;
            }
        }elsif ($line =~ /mod_rewrite\soptions:\s(.*)/){
            $modrewopts = $1;
        }elsif ($line =~ /Old\sDestination:\s(.*)/){
            $old_dest = $1;
        }elsif ($line =~ /^\s+User:\s(.*)/){
            $user = $1;
        }elsif ($line =~ /Timestamp:\s(.*)/ and $startEntry){
            $strtimestamp = $1;
            if ($isNewEntry){
                push (@CombinedList,{
                    domain     => $domain,
                    transType  => "NEW",
                    from       => $fromURI,
                    to         => $toURI,
                    ruleType   => $ruleType,
                    modrewopts => $modrewopts,
                    user       => $user,
                    timestamp  => strtodate($strtimestamp)
                });
                $isNewEntry = 0;
            }elsif ($isUpdateEntry){
                push (@CombinedList,{
                    domain     => $domain,
                    transType  => "UPDATE",
                    from       => $fromURI,
                    to         => $toURI,
                    ruleType   => $ruleType,
                    modrewopts => $modrewopts,
                    old_dest   => $old_dest,
                    user       => $user,
                    timestamp  => strtodate($strtimestamp)
                });
                $isUpdateEntry = 0;
            }elsif ($isDeleteEntry){
                push (@CombinedList,{
                    domain     => $domain,
                    transType  => "DELETE",
                    rule       => $fromURI,
                    user       => $user,
                    timestamp  => strtodate($strtimestamp)
                });
                $isDeleteEntry = 0;
            }
        }elsif ($line =~ /END\sRULE/){
            $startEntry = 0;
        }elsif ($line =~ /START\sSECURITY\sALERT/){
            $securitycounter++;
            $startSecurityEntry = 1;
            $isSecurityEntry = 1;
        }elsif ($line =~ /Domain\(s\):\s+(.*)/ and $startSecurityEntry){
            $secDomains = $1;
        }elsif ($line =~ /From:\s(.*)/ and $startSecurityEntry){
            $fromURI = $1;
        }elsif ($line =~ /To:\s(.*)/ and $startSecurityEntry){
            $toURI = $1;
        }elsif ($line =~ /Rule\sType:\s(.*)/ and $startSecurityEntry){
            $ruleType = $1;
        }elsif ($line =~ /Attempted\sUser:\s(.*)/ and $startSecurityEntry){
            $attemptedUser = $1;
        }elsif ($line =~ /Timestamp:\s(.*)/ and $startSecurityEntry){
            $strtimestamp = $1;
            if ($isSecurityEntry){
                push (@SecurityList,{
                    domains    => $secDomains,
                    from       => $fromURI,
                    to         => $toURI,
                    ruleType   => $ruleType,
                    attempt    => $attemptedUser,
                    timestamp  => strtodate($strtimestamp)
                });
                $isSecurityEntry = 0;
            }
        }elsif ($line =~ /END\sSECURITY\sRULE/){
            $startSecurityEntry = 0;
        }
    }
    if ($opt_quarter eq "current"){
        my $currentDate = strtodate(scalar(localtime(time + 0)));
        if ($currentDate >= strtodate2("s", $q1start) and $currentDate <= strtodate2("e", $q1end) ){
            $firstEntryDate = strtodate2("s",$q1start);
            $lastEntryDate = strtodate2("e",$q1end);
        }elsif ($currentDate >= strtodate2("s", $q2start) and $currentDate <= strtodate2("e", $q2end)){
            $firstEntryDate = strtodate2("s",$q2start);
            $lastEntryDate = strtodate2("e",$q2end);
        }elsif ($currentDate >= strtodate2("s", $q3start) and $currentDate <= strtodate2("e", $q3end)){
            $firstEntryDate = strtodate2("s",$q3start);
            $lastEntryDate = strtodate2("e",$q3end);
        }elsif ($currentDate >= strtodate2("s", $q4start) and $currentDate <= strtodate2("e", $q4end)){
            $firstEntryDate = strtodate2("s",$q4start);
            $lastEntryDate = strtodate2("e",$q4end);
        }
        
    }elsif ($opt_quarter eq "1"){
        $firstEntryDate = strtodate2("s",$q1start);
        $lastEntryDate = strtodate2("e",$q1end);
    }elsif ($opt_quarter eq "2"){
        $firstEntryDate = strtodate2("s",$q2start);
        $lastEntryDate = strtodate2("e",$q2end);
    }elsif ($opt_quarter eq "3"){
        $firstEntryDate = strtodate2("s",$q3start);
        $lastEntryDate = strtodate2("e",$q3end);
    }elsif ($opt_quarter eq "4"){
        $firstEntryDate = strtodate2("s",$q4start);
        $lastEntryDate = strtodate2("e",$q4end);
    }else{
        $firstEntryDate = $CombinedList[0]{timestamp};
        $lastEntryDate  = $CombinedList[scalar @CombinedList -1 ]{timestamp};
        
    }
    if ($opt_startdate){
        $firstEntryDate = DateTime->new(
        year   => strtodate2("s",$opt_startdate)->year,
        month  => strtodate2("s",$opt_startdate)->month,
        day    => strtodate2("s",$opt_startdate)->day,
        hour   => "00",
        minute => "00",
        second => "00"
        );
    }
    if ($opt_enddate){
        $lastEntryDate = DateTime->new(
        year   => strtodate2("e",$opt_enddate)->year,
        month  => strtodate2("e",$opt_enddate)->month,
        day    => strtodate2("e",$opt_enddate)->day,
        hour   => "23",
        minute => "59",
        second => "59"
        );
    }
    if ($byDate){
        
        $srchDate = DateTime->new(
        year   => strtodate2("s",$opt_date)->year,
        month  => strtodate2("s",$opt_date)->month,
        day    => strtodate2("s",$opt_date)->day,
        hour   => "00",
        minute => "00",
        second => "00"
        );
    }
    if ($reportMode){
        my $header = 0;
        for (my $z = 0; $z < scalar(@CombinedList); $z++){
            push (@uniqUsers, $CombinedList[$z]{user});
            push (@uniqDomains, $CombinedList[$z]{domain});
        }
        @uniqUsers =   uniq(@uniqUsers);
        @uniqDomains = uniq(@uniqDomains);
        
        if ($opt_rep_users){
            $header = 1;
            foreach my $recuser (@uniqUsers){
                for (my $x = 0; $x < scalar(@CombinedList); $x++){
                    if ($CombinedList[$x]{timestamp} >= $firstEntryDate and $CombinedList[$x]{timestamp} <= $lastEntryDate){
                        if ($CombinedList[$x]{user} eq $recuser){
                            if ($CombinedList[$x]{transType} eq "NEW"){
                                $repusernewcounter++;
                                if ($CombinedList[$x]{ruleType} eq "vanity"){
                                    $repuservanitycounter++;
                                }elsif ($CombinedList[$x]{ruleType} eq "redirect"){
                                    $repuserredirectcounter++;
                                }
                            }elsif ($CombinedList[$x]{transType} eq "UPDATE"){
                                $repuserupdatecounter++;
                                if ($CombinedList[$x]{ruleType} eq "vanity"){
                                    $repuservanitycounter++;
                                }elsif ($CombinedList[$x]{ruleType} eq "redirect"){
                                    $repuserredirectcounter++;
                                }
                            }elsif ($CombinedList[$x]{transType} eq "DELETE"){
                                $repuserdeletecounter++;
                                }
                            }
                        }
                    }
                
                collectUserStats($recuser,$repusernewcounter,$repuserupdatecounter,$repuserdeletecounter,$repuservanitycounter,$repuserredirectcounter);
                $repusernewcounter      = 0;
                $repuserupdatecounter   = 0;
                $repuserdeletecounter   = 0;
                $repuservanitycounter   = 0;
                $repuserredirectcounter = 0;
            }
            for (my $i = 0 ; $i < scalar(@userStats) ; $i++){
                $repnewcount      += $userStats[$i]{NEW};
                $repupdatecount   += $userStats[$i]{UPDATE};
                $repdeletecount   += $userStats[$i]{DELETE};
                $repvanitycount   += $userStats[$i]{vanity};
                $repredirectcount += $userStats[$i]{redirect};
            }
            
            if ($opt_notify){
                emailReportHeader($repnewcount,$repupdatecount,$repdeletecount,$repvanitycount,$repredirectcount,datetostr($firstEntryDate,"base"),datetostr($lastEntryDate,"base"));
            }
            printReportHeader($repnewcount,$repupdatecount,$repdeletecount,$repvanitycount,$repredirectcount,datetostr($firstEntryDate,"base"),datetostr($lastEntryDate,"base"));
            my $detectanyrule = $repnewcount+$repupdatecount+$repdeletecount;
            if ($detectanyrule){
            print "\n                         ------<( USER STATISTICS )>------\n";
 	        print " ======================================================================================\n";
            if ($opt_notify){
                    $EmailMessage .= "\n                         ------<( USER STATISTICS )>------\n\n";
                    $EmailMessage .= " ======================================================================================\n";
            }
            for (my $c = 0 ; $c < scalar(@userStats);  $c++){
                my $transCount = ($userStats[$c]{NEW} + $userStats[$c]{UPDATE} + $userStats[$c]{DELETE});
                if ($transCount){
                    printUserStats($userStats[$c]{user},$userStats[$c]{NEW},$userStats[$c]{UPDATE},$userStats[$c]{DELETE},$userStats[$c]{vanity},$userStats[$c]{redirect});
                    if ($opt_notify){
                        emailUserStats($userStats[$c]{user},$userStats[$c]{NEW},$userStats[$c]{UPDATE},$userStats[$c]{DELETE},$userStats[$c]{vanity},$userStats[$c]{redirect});
                    }
                }
            }
        }
            if ($opt_rep_domains){
                print "\n\n";
		if ($opt_notify){
                	$EmailMessage .= "\n\n";
		}
            }
        }
        if ($opt_rep_domains){
            foreach my $recdomain (@uniqDomains){
                for (my $x = 0; $x < scalar(@CombinedList); $x++){
                    if ($CombinedList[$x]{timestamp} >= $firstEntryDate and $CombinedList[$x]{timestamp} <= $lastEntryDate){
                        if ($CombinedList[$x]{domain} eq $recdomain){
                            if ($CombinedList[$x]{transType} eq "NEW"){
                                $repdomainnewcounter++;
                                if ($CombinedList[$x]{ruleType} eq "vanity"){
                                    $repdomainvanitycounter++;
                                }elsif ($CombinedList[$x]{ruleType} eq "redirect"){
                                    $repdomainredirectcounter++;
                                }
                            }elsif ($CombinedList[$x]{transType} eq "UPDATE"){
                                $repdomainupdatecounter++;
                                if ($CombinedList[$x]{ruleType} eq "vanity"){
                                    $repdomainvanitycounter++;
                                }elsif ($CombinedList[$x]{ruleType} eq "redirect"){
                                    $repdomainredirectcounter++;
                                }
                            }elsif ($CombinedList[$x]{transType} eq "DELETE"){
                                $repdomaindeletecounter++;
                            }
                        }
                    }
                }
                
                collectDomainStats($recdomain,$repdomainnewcounter,$repdomainupdatecounter,$repdomaindeletecounter,$repdomainvanitycounter,$repdomainredirectcounter);
                $repdomainnewcounter      = 0;
                $repdomainupdatecounter   = 0;
                $repdomaindeletecounter   = 0;
                $repdomainvanitycounter   = 0;
                $repdomainredirectcounter = 0;
            }
            if (not $header){
                for (my $i = 0 ; $i < scalar(@domainStats) ; $i++){
                    $repnewcount      += $domainStats[$i]{NEW};
                    $repupdatecount   += $domainStats[$i]{UPDATE};
                    $repdeletecount   += $domainStats[$i]{DELETE};
                    $repvanitycount   += $domainStats[$i]{vanity};
                    $repredirectcount += $domainStats[$i]{redirect};
                }
                
                if ($opt_notify){
                    emailReportHeader($repnewcount,$repupdatecount,$repdeletecount,$repvanitycount,$repredirectcount,datetostr($firstEntryDate,"base"),datetostr($lastEntryDate,"base"));
                }
                printReportHeader($repnewcount,$repupdatecount,$repdeletecount,$repvanitycount,$repredirectcount,datetostr($firstEntryDate,"base"),datetostr($lastEntryDate,"base"));
            }
            my $detectanyrule = $repnewcount+$repupdatecount+$repdeletecount;
            if ($detectanyrule){
            print "\n                        ------<( DOMAIN STATISTICS )>------\n";
 	        print " ======================================================================================\n";
            if ($opt_notify){
                    $EmailMessage .= "\n                        ------<( DOMAIN STATISTICS )>------\n\n";
                    $EmailMessage .= " ======================================================================================\n";
            }
            for (my $c = 0 ; $c < scalar(@domainStats); $c++){
                my $transCount = ($domainStats[$c]{NEW} + $domainStats[$c]{UPDATE} + $domainStats[$c]{DELETE});
                if ($transCount){
                    printDomainStats($domainStats[$c]{domain},$domainStats[$c]{NEW},$domainStats[$c]{UPDATE},$domainStats[$c]{DELETE},$domainStats[$c]{vanity},$domainStats[$c]{redirect});
                    if ($opt_notify){
                        emailDomainStats($domainStats[$c]{domain},$domainStats[$c]{NEW},$domainStats[$c]{UPDATE},$domainStats[$c]{DELETE},$domainStats[$c]{vanity},$domainStats[$c]{redirect});
                    }
                }
             }
          }
       }
    }
    if (not $opt_security and not $reportMode){
        for (my $j = 0; $j < scalar(@CombinedList); $j++){
            if ($byRuleURI){
                if (($transIsNew or $transIsAll) and $CombinedList[$j]{transType} eq "NEW"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ($CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{from} =~ /\Q$opt_rule\E/){
                                            if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                                push (@ResultList,{
                                                    domain     => $CombinedList[$j]{domain},
                                                    transType  => "NEW",
                                                    from       => $CombinedList[$j]{from},
                                                    to         => $CombinedList[$j]{to},
                                                    ruleType   => $CombinedList[$j]{ruleType},
                                                    modrewopts => $CombinedList[$j]{modrewopts},
                                                    user       => $CombinedList[$j]{user},
                                                    timestamp  => $CombinedList[$j]{timestamp}
                                                });
                                            }
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{from} =~ /\Q$opt_rule\E/){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "NEW",
                                                from       => $CombinedList[$j]{from},
                                                to         => $CombinedList[$j]{to},
                                                ruleType   => $CombinedList[$j]{ruleType},
                                                modrewopts => $CombinedList[$j]{modrewopts},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                if (($transIsUpdate or $transIsAll) and $CombinedList[$j]{transType} eq "UPDATE"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ( $CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{from} =~ /\Q$opt_rule\E/){
                                            if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                                push (@ResultList,{
                                                    domain     => $CombinedList[$j]{domain},
                                                    transType  => "UPDATE",
                                                    from       => $CombinedList[$j]{from},
                                                    to         => $CombinedList[$j]{to},
                                                    ruleType   => $CombinedList[$j]{ruleType},
                                                    modrewopts => $CombinedList[$j]{modrewopts},
                                                    old_dest   => $CombinedList[$j]{old_dest},
                                                    user       => $CombinedList[$j]{user},
                                                    timestamp  => $CombinedList[$j]{timestamp}
                                                });
                                            }
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{from} =~ /\Q$opt_rule\E/){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "UPDATE",
                                                from       => $CombinedList[$j]{from},
                                                to         => $CombinedList[$j]{to},
                                                ruleType   => $CombinedList[$j]{ruleType},
                                                modrewopts => $CombinedList[$j]{modrewopts},
                                                old_dest   => $CombinedList[$j]{old_dest},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (($transIsDelete or $transIsAll) and $CombinedList[$j]{transType} eq "DELETE"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ( $CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{rule} =~ /\Q$opt_rule\E/){
                                            if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                                push (@ResultList,{
                                                    domain     => $CombinedList[$j]{domain},
                                                    transType  => "DELETE",
                                                    rule       => $CombinedList[$j]{rule},
                                                    user       => $CombinedList[$j]{user},
                                                    timestamp  => $CombinedList[$j]{timestamp}
                                                });
                                            }
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{rule} =~ /\Q$opt_rule\E/){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "DELETE",
                                                rule       => $CombinedList[$j]{rule},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
            }else{
                
                if (($transIsNew or $transIsAll) and $CombinedList[$j]{transType} eq "NEW"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ($CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "NEW",
                                                from       => $CombinedList[$j]{from},
                                                to         => $CombinedList[$j]{to},
                                                ruleType   => $CombinedList[$j]{ruleType},
                                                modrewopts => $CombinedList[$j]{modrewopts},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                        push (@ResultList,{
                                            domain     => $CombinedList[$j]{domain},
                                            transType  => "NEW",
                                            from       => $CombinedList[$j]{from},
                                            to         => $CombinedList[$j]{to},
                                            ruleType   => $CombinedList[$j]{ruleType},
                                            modrewopts => $CombinedList[$j]{modrewopts},
                                            user       => $CombinedList[$j]{user},
                                            timestamp  => $CombinedList[$j]{timestamp}
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
                
                if (($transIsUpdate or $transIsAll) and $CombinedList[$j]{transType} eq "UPDATE"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ( $CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "UPDATE",
                                                from       => $CombinedList[$j]{from},
                                                to         => $CombinedList[$j]{to},
                                                ruleType   => $CombinedList[$j]{ruleType},
                                                modrewopts => $CombinedList[$j]{modrewopts},
                                                old_dest   => $CombinedList[$j]{old_dest},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                        push (@ResultList,{
                                            domain     => $CombinedList[$j]{domain},
                                            transType  => "UPDATE",
                                            from       => $CombinedList[$j]{from},
                                            to         => $CombinedList[$j]{to},
                                            ruleType   => $CombinedList[$j]{ruleType},
                                            modrewopts => $CombinedList[$j]{modrewopts},
                                            old_dest   => $CombinedList[$j]{old_dest},
                                            user       => $CombinedList[$j]{user},
                                            timestamp  => $CombinedList[$j]{timestamp}
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
                if (($transIsDelete or $transIsAll) and $CombinedList[$j]{transType} eq "DELETE"){
                    foreach my $srchdom (@opt_domain){
                        if (not $byDate){
                            if ($CombinedList[$j]{timestamp} >= $firstEntryDate and $CombinedList[$j]{timestamp} <= $lastEntryDate){
                                if ( $CombinedList[$j]{domain} =~ $srchdom){
                                    if ($CombinedList[$j]{user} =~ $opt_user){
                                        if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                            push (@ResultList,{
                                                domain     => $CombinedList[$j]{domain},
                                                transType  => "DELETE",
                                                rule       => $CombinedList[$j]{rule},
                                                user       => $CombinedList[$j]{user},
                                                timestamp  => $CombinedList[$j]{timestamp}
                                            });
                                        }
                                    }
                                }
                            }
                        }elsif ($byDate and 
				($CombinedList[$j]{timestamp}->day == $srchDate->day and 
				 $CombinedList[$j]{timestamp}->month == $srchDate->month and 
				 $CombinedList[$j]{timestamp}->year == $srchDate->year)){
                            if  ($CombinedList[$j]{domain} =~ $srchdom){
                                if ($CombinedList[$j]{user} =~ $opt_user){
                                    if ($CombinedList[$j]{ruleType} =~ $opt_ruletype){
                                        push (@ResultList,{
                                            domain     => $CombinedList[$j]{domain},
                                            transType  => "DELETE",
                                            rule       => $CombinedList[$j]{rule},
                                            user       => $CombinedList[$j]{user},
                                            timestamp  => $CombinedList[$j]{timestamp}
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        for (my $i = 0; $i < scalar(@ResultList); $i++){
            
            if ($ResultList[$i]{transType} eq "NEW"){
                printNEWEntry(
                $ResultList[$i]{domain},
                $ResultList[$i]{from},
                $ResultList[$i]{to},
                $ResultList[$i]{ruleType},
                $ResultList[$i]{modrewopts},
                $ResultList[$i]{user},
                $ResultList[$i]{timestamp}
                );
            }
            
            if ($ResultList[$i]{transType} eq "UPDATE"){
                printUPDATEEntry(
                $ResultList[$i]{domain},
                $ResultList[$i]{from},
                $ResultList[$i]{to},
                $ResultList[$i]{ruleType},
                $ResultList[$i]{modrewopts},
                $ResultList[$i]{old_dest},
                $ResultList[$i]{user},
                $ResultList[$i]{timestamp}
                );
            }
            
            if ($ResultList[$i]{transType} eq "DELETE"){
                printDELETEEntry(
                $ResultList[$i]{domain},
                $ResultList[$i]{rule},
                $ResultList[$i]{user},
                $ResultList[$i]{timestamp}
                );
            }
        }
    }elsif ($opt_security and not $reportMode){
        
        for (my $k = 0; $k < scalar(@SecurityList); $k++){
            printSECURITYEntry(
            $SecurityList[$k]{domains},
            $SecurityList[$k]{from},
            $SecurityList[$k]{to},
            $SecurityList[$k]{ruleType},
            $SecurityList[$k]{attempt},
            $SecurityList[$k]{timestamp}
            );
        }
    }
    
    $firstDateInFile = datetostr($CombinedList[0]{timestamp},"base");
    $lastDateInFile  = datetostr($CombinedList[scalar (@CombinedList)-1]{timestamp},"base");
    
    if ( not $reportMode){
        print "\n";
        if ($opt_security){
            print " Returned (".scalar(@SecurityList).") security incident(s)\n";
        }else{
            if (scalar(@ResultList) == 1 ){
                print " Query Returned (".scalar(@ResultList).") Entry\n";
            }else{
                print " Query Returned (".scalar(@ResultList).") Entries\n";
            }
        }
        print " -------------\n";
    }else{
        print "\n";
    }
    
    print " RECORDS IN FILE ARE FROM: ".$firstDateInFile." TO ".$lastDateInFile."\n";
    print " All      : ".$allcounter."\n";
    print " New      : ".$newcounter."\n";
    print " Updated  : ".$updatecounter."\n";
    print " Deleted  : ".$deletecounter."\n";
    print " Vanity   : ".$vanitycounter."\n";
    print " Redirect : ".$redirectcounter."\n";
    print " Security : ".$securitycounter."\n\n";
    if ($opt_notify){
    $EmailMessage .= "\n RECORDS IN FILE ARE FROM: ".$firstDateInFile." TO ".$lastDateInFile."\n";
    $EmailMessage .= " All      : ".$allcounter."\n";
    $EmailMessage .= " New      : ".$newcounter."\n";
    $EmailMessage .= " Updated  : ".$updatecounter."\n";
    $EmailMessage .= " Deleted  : ".$deletecounter."\n";
    $EmailMessage .= " Vanity   : ".$vanitycounter."\n";
    $EmailMessage .= " Redirect : ".$redirectcounter."\n";
    $EmailMessage .= " Security : ".$securitycounter."\n\n";
    }
}
sub collectUserStats{
    my ($user, $new, $update, $delete, $vanity, $redirect) = @_;
    push (@userStats,{user => $user, 
		      NEW => $new, 
		      UPDATE => $update, 
                      DELETE => $delete, 
                      vanity => $vanity, 
                      redirect => $redirect});
}
sub collectDomainStats{
    my ($domain, $new, $update, $delete, $vanity, $redirect) = @_;
    push (@domainStats,{domain => $domain, 
                        NEW => $new, 
                        UPDATE => $update, 
                        DELETE => $delete, 
                        vanity => $vanity, 
                        redirect => $redirect});
}
sub emailUserStats{
    my ($user, $new, $update, $delete, $vanity, $redirect) = @_;
    open(USERSTATOUTEMAIL,">> ",\$EmailMessage);
    write (USERSTATOUTEMAIL);
    
format USERSTATOUTEMAIL =
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    vanity: @<<<<<< redirect: @<<<<<<
 $user,$vanity,$redirect
 Transaction Types:         new: @<<<<<< update: @<<<<<< delete:   @<<<<<< sum: @<<<<<<
 $new,$update,$delete,($new+$update+$delete)
 ======================================================================================
.
}
sub emailDomainStats{
    my ($domain, $new, $update, $delete, $vanity, $redirect) = @_;
    open(DOMAINSTATOUTEMAIL,">> ",\$EmailMessage);
    write (DOMAINSTATOUTEMAIL);
    
format DOMAINSTATOUTEMAIL =
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  vanity: @<<<<<< redirect: @<<<<<<
 $domain,$vanity,$redirect
 Transaction Types:         new: @<<<<<< update: @<<<<<< delete:   @<<<<<< sum: @<<<<<<
 $new,$update,$delete,($new+$update+$delete)
 ======================================================================================
.
}
sub printUserStats{
     my ($user, $new, $update, $delete, $vanity, $redirect) = @_;
     open(USERSTATOUT,"> ".'-');
     write (USERSTATOUT);
    
format USERSTATOUT =
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    vanity: @<<<<<< redirect: @<<<<<<
 $user,$vanity,$redirect
 Transaction Types:         new: @<<<<<< update: @<<<<<< delete:   @<<<<<< sum: @<<<<<<
 $new,$update,$delete,($new+$update+$delete)
 ======================================================================================
.
}
sub printDomainStats{
    my ($domain, $new, $update, $delete, $vanity, $redirect) = @_;
    open(DOMAINSTATOUT,"> ".'-');
    write (DOMAINSTATOUT);
    
format DOMAINSTATOUT =
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  vanity: @<<<<<< redirect: @<<<<<<
 $domain,$vanity,$redirect
 Transaction Types:         new: @<<<<<< update: @<<<<<< delete:   @<<<<<< sum: @<<<<<<
 $new,$update,$delete,($new+$update+$delete)
 ======================================================================================
.
}
sub printNEWEntry{
    
    my ($domain, $fromURI, $toURI, $ruleType, $modrewopts, $user, $timestamp) = @_;
    open(NEWOUT,"> ".'-');
    write NEWOUT;
    format NEWOUT =
 ===== START RULE =================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 "NEW"
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $fromURI
 To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $toURI
 Rule Type: @<<<<<<<<<
 $ruleType
 mod_rewrite options: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $modrewopts
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $user
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 datetostr($timestamp)
 ===== END RULE ===================================================================================================================================
.
}
sub printUPDATEEntry{
    
    my ($domain, $fromURI, $toURI, $ruleType, $modrewopts, $old_dest, $user, $timestamp) = @_;
    open(UPDATEOUT,"> ".'-');
    write UPDATEOUT;
    format UPDATEOUT =
 ===== START RULE =================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 "UPDATE"
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $fromURI
 To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $toURI
 Rule Type: @<<<<<<<<<
 $ruleType
 mod_rewrite options: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $modrewopts
 Old Destination: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $old_dest
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $user
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 datetostr($timestamp)
 ===== ENDRULE ====================================================================================================================================
.
}
sub printDELETEEntry{
    
    my ($domain, $rule, $user, $timestamp) = @_;
    open(DELETEOUT,"> ".'-');
    write DELETEOUT;
    format DELETEOUT =
 ===== START RULE =================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 "DELETE"
 Rule: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $rule
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $user
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 datetostr($timestamp)
 ===== END RULE ===================================================================================================================================
.
}
sub printSECURITYEntry{
    
    my ($domains, $fromURI, $toURI, $ruleType, $attemptUser, $timestamp) = @_;
    open(SECURITYOUT,"> ".'-');
    write SECURITYOUT;
    format SECURITYOUT =
 <><><><><> START SECURITY ALERT <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
 Domain(s): @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domains
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $fromURI
 To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $toURI
 Rule Type: @<<<<<<<<<
 $ruleType
 Attempted User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $attemptUser
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 datetostr($timestamp)
 <><><><><> END SECURITY ALERT <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
.

}
sub printReportHeader{
    
    my  ($new, $update, $delete, $vanity, $redirect,$firstdate,$lastdate) = @_;
    print " \n              REPORT FOR PERIOD OF ".$firstdate." TO ".$lastdate."\n";
    print "              -----------------------------------------------\n";
    open (HEADEROUT, "> "."-");
    write(HEADEROUT);

    format HEADEROUT =
                        TYPES              TRANSACTIONS
                        -----              ------------
                        vanity:   @<<<<<   new:    @<<<<<
                        $vanity,$new
                        redirect: @<<<<<   update: @<<<<<
                        $redirect,$update
                                           delete: @<<<<<
                                           $delete
                                           -------------
                                           Sum:    @<<<<<
                                           $new+$update+$delete

.

}
sub emailReportHeader{

    my  ($new, $update, $delete, $vanity, $redirect,$firstdate,$lastdate) = @_;
    $EmailMessage .= " \n              REPORT FOR PERIOD OF ".$firstdate." TO ".$lastdate."\n";
    $EmailMessage .= "              ---------------------------------------------------------------\n";
    open (HEADEROUTEMAIL, ">> ", \$EmailMessage);
    write(HEADEROUTEMAIL);
    
    format HEADEROUTEMAIL =
                        TYPES                      TRANSACTIONS
                        ---------                    -------------------
                        vanity:   @<<<<<          new:    @<<<<<
                        $vanity,$new
                        redirect: @<<<<<      update: @<<<<<
                        $redirect,$update
                                                            delete: @<<<<<
                                                            $delete
                                                            -------------------
                                                             Sum:    @<<<<<
                                                             $new+$update+$delete
    
.
}
sub mailer {

    my $mailer = "/usr/sbin/sendmail -t";
    open (MAIL,"|$mailer") or die "Error opening the sendmail program: $!\n";
    write MAIL;
    
format MAIL =
From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	$localemail
To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	"$mail_addresses{Khaled}"
Subject: rewrite rules statistics report.
    
@*
$EmailMessage
.    
close MAIL;    
}
sub Usage{
    
    print " ____        _             ____  _        _                \n";
    print "|  _ \\ _   _| | ___  ___  / ___|| |_ __ _| |_ ___         \n";
    print "| |_) | | | | |/ _ \\/ __| \\___ \\| __/ _` | __/ __|      \n";
    print "|  _ <| |_| | |  __/\\__ \\  ___) | || (_| | |_\__ \\      \n";
    print "|_| \\_\\\\__,_|_|\\___||___/ |____/ \\__\\__,_|\\__|___/  \n";
    print "                                                           \n";
    print "                                                           \n";
    print "           Version $VERSION\n";
    print "           By Khaled Ahmed (SDG Team)\n";
    print "           Copyright (C) 2012-2013\n\n";
    print "Options:\n";
    print "         [--start-date] and [--end-date]  List entries between start & end dates (fmt dd-mm-yyyy)\n";
    print "         [--date]                         List entries in date (fmt dd-mm-yyyy)\n";
    print "         [--domain]                       List entries for domain(s) (domains separated by ',')\n";
    print "         [--rule]                         List actions performed on a rule\n";
    print "         [--rule-type]                    List by either [vanity or redirect]\n";
    print "         [--transaction]                  List by the transaction type [new,update,delete]\n";
    print "         [--user]                         List by user, full name enclosed by double quotes i.e \"John Doe\"\n";
    print "         [--security]                     List all security incidents recorded in the current log file\n";
    print "         [--quarter] or [-Q]              List entries by quarter number [1,2,3,4 or current]\n";
    print "         [--report]                       Switch to report mode\n";
    print "         [--list-users]                   Print user statistics   (Only in report mode)\n";
    print "         [--list-domains]                 Print domain statistics (Only in report mode)\n";
    print "         [--notify]                       Send the aggregated report to the management (Only in report mode)\n";
    print "         [--version] or [-v]              Print the version\n";
    print "         [--help] or [-h]                 Show this help message.\n\n";
    exit (0);
}
validateOptions();
parselog();
if ($opt_notify){
    mailer();
}

__END__
