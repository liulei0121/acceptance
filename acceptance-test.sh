#!/bin/sh
# Copyright (C) 2012 Intel Corporation 
#    
# This program is free software; you can redistribute it and/or 
# modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation; either version 2 
# of the License, or (at your option) any later version. 
#    
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
# GNU General Public License for more details. 
#   
# You should have received a copy of the GNU General Public License 
# along with this program; if not, write to the Free Software 
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. 
#
# Authors:
#     Li jun <junx.b.li@intel.com>
# 

if [ $# -ne 1 ];then
    echo "please specify your template recipe file"
    echo "$0 <template recipe>"
    exit 1
fi
pro=`ps aux|grep cats-client|grep usr|grep bin|grep recipe_test_bat`
if [ $? -eq 0 -a -n "$pro" ];then
    echo "the previous bat test is still running, cancel this test"
    exit 1
fi

newimage="`python /opt/acceptance/src/consumer.py | awk -F\' '{print $4}' `"
MAX_LEN=80
tmpdir="/opt/acceptance/data/CACHE/"
tmpreport="/opt/acceptance/data/CACHE/tmpreport"
tmpfailreport="/opt/acceptance/data/CACHE/tmpfailreport"
tmprunninglog="/opt/acceptance/data/CACHE/tmprunninglog"
tmpCase="/opt/acceptance/data/CACHE/tmp_case"

if [ -f $tmpdir ];then
    mkdir -P $tmpdir
fi

if echo $newimage | grep "handset|ivi" ;then
   image_date="`python /opt/acceptance/src/consumer.py| awk -F\' '{print $4}' | sed "s/^.*_//g" | sed "s/-.*//g"`"
elif echo $newimage | grep "RSA"; then
   image_date="`python /opt/acceptance/src/consumer.py| awk -F\' '{print $4}' | sed "s/^.*_//g" | sed "s/\.tar.*//g"`"
else
   echo "unknow image"
   exit 1
fi

ivi_test () {
   MAIL_ADDRESS="/opt/acceptance/data/ivi/mail_address_ivi"
   MAIL_ADDRESS_ERROR="/opt/acceptance/data/ivi/mail_address_error_ivi"
   TEMPLATE_REPORT="/opt/acceptance/data/ivi/template_report_ivi"
   TEMPLATE_FAIL="/opt/acceptance/data/ivi/template_fail_ivi"
   SUBJECT="[ IVI-acceptance-test ] - "
   RECIPE_FILE="/opt/acceptance/data/ivi/ivi_acceptance.ini"
}

lunchbox_test () {
   MAIL_ADDRESS="/opt/lunchbox-automation/data/mail_address_lb"
   MAIL_ADDRESS_ERROR="/opt/acceptance/data/mail_address_error_lb"
   TEMPLATE_COMPLETED="/opt/acceptance/data/template_completed_lb"
   TEMPLATE_PASS="/opt/acceptance/data/template_pass_lb"
   TEMPLATE_FAIL="/opt/acceptance/data/template_fail_lb"
   SUBJECT="[Lunchbox-Acceptance-Test]"
   RECIPE_FILE="/opt/acceptance/data/lunchbox/lunchbox_acceptance.ini"
}

pr3_test () {
   MAIL_ADDRESS="/opt/acceptance/data/pr3/mail_address_pr3"
   MAIL_ADDRESS_ERROR="/opt/acceptance/data/pr3/mail_address_error_pr3"
   TEMPLATE_COMPLETED="/opt/acceptance/data/pr3/template_completed_pr3"
   TEMPLATE_PASS="/opt/acceptance/data/pr3/template_pass_pr3"
   RECIPE_FILE="/opt/acceptance/date/pr3/pr3_acceptance.ini"
   TEMPLATE_FAIL="/opt/acceptance/data/pr3/template_fail_pr3"
   SUBJECT="[PR3-acceptance-test]"
}

prerelease_test () {
   MAIL_ADDRESS="/opt/pre-pretrunk-autotest/data/mail_address"
   MAIL_ADDRESS_ERROR="/opt/pre-pretrunk-autotest/data/mail_address_error"
   TEMPLATE_COMPLETED="/opt/pre-pretrunk-autotest/data/pretemplate_completed"
   TEMPLATE_PASS="/opt/pre-pretrunk-autotest/data/pretemplate_pass"
   RECIPE_FILE="/opt/acceptance/date/pr3/pr3_acceptance.ini"
   TEMPLATE_FAIL="/opt/pre-pretrunk-autotest/data/pretemplate_fail"
   SUBJECT="[PR3-PreRelease-Test]"
   REPORT_FILE="/opt/acceptance/data/CACHE/REPORT.log"

##Distinguish image
if echo $newimage | grep "ivi"
   ivi_test
elif echo $newimage | grep "RSA";then
   lunchbox_test
elif echo $newimage | grep "handset-blackbay-tizen-mobile_";then
   pr3_test
elif echo $newimage | grep "staging_";then
   prerelease_test
else
   echo "unknow image"
   exit 1 
fi


address=`cat $MAIL_ADDRESS | sed "s/;/ /g"
addresserror=`cat $MAIL_ADDRESS_ERROR | sed "s/;/ /g"

#modify recipe
cp -f $RECIPE_FILE recipe_test_bat.ini
sed -i "s/image_date/$image_date/g" recipe_test_bat.ini
time=`date +%m%d%H%M%Y`
echo $time
sed -i "s/changedate/$time/g" recipe_test_bat.ini

#submit test request
rm -rf /tmp/running_bat.log
cats-client submit_recipe -f recipe_test_bat.ini 2>&1 | tee /tmp/running_bat.log

sleep 5
i=0
declare -a array
recipe=0
if [ -f $tmprunninglog ];then
    #get the recipe ID and report_site
    cat $tmprunninglog | grep "Result dir =" > /dev/null
    if [ $? -ne 0 ];then
         echo "failure found"
         cp -f $TEMPLATE_FAIL fail_report
         sed -i "s/_image_tested/$image_date/g" fail_report
         sed -i -e "s/..3[3,1,4]m//g" -e "s/..0m//g" $tmprunninglog
         error=`cat /tmp/running_bat.log | grep -i CRITICAL | awk '{$2="";$3="";print $0 }'`
         echo "$error" | tee -a fail_report
         cat fail_report | grep -i "CRITICAL"
         if [ $? -ne 0 ];then
         cat fail_report | mutt $addresserror -s "$SUBJECT $image_date FAIL(no critical info)" -a "/tmp/running_bat.log"
         else
         cat fail_report | mutt $address -s "$SUBJECT $image_date FAIL"  -a "/tmp/running_bat.log"
         fi
         cp -f $CURF $CACHEF
         rm -rf fail_report
         exit 2
    fi
    rst=`cat /tmp/running_bat.log | grep "Result dir ="`
    echo "-------rst:$rst--------"
    recipe=${rst#*tmp/}
    echo "------recipe:$recipe------"
    temp=`cat /tmp/running_bat.log|grep http|grep intel`
    report_site=${temp#*successful: }
    #get all the result files of the recipe
    dir="/tmp/$recipe/"
    echo "-------dir:$dir------"
    cp $tmprunninglog $dir/running_bat.log
    for item in `ls $dir`
        do
        echo "-----item:$item--------"
            if [ -f $dir$item ];then
                array[$i]=$dir$item
                let i+=1
            elif [ -d $dir$item ] ; then
                for sub_item in `ls /tmp/$recipe/$item`
                    do
                        array[$i]=$dir$item"/"$sub_item
                        let i+=1
                    done
            fi
        done
     echo "total $i files found! they are:"
     for file in ${array[@]}
     do
         echo $file 
     done
else
    echo "no running log /tmp/running_bat.log found"
    exit 1
fi

#collect date
pass_num=0
fail_num=0
block_num=0

echo "-------- before array entered --------"
for file in ${array[@]}
do
    echo "------ array entered -------"
    echo `pwd`
    echo "-------file:$file---------"
    tail -n 1 $file | grep "</test_definition>" >/dev/null
    if [ $? -eq 0 ];then
        echo "------ array entered and condition is true  -------"
        echo $file
        pNum=`cat $file | grep "<testcase.*component=.*result=\"PASS\"" | wc -l`
        fNum=`cat $file | grep "<testcase.*component=.*result=\"FAIL\"" | wc -l`
        bNum=`cat $file | grep "<testcase.*component=.*result=\"BLOCK\"" | wc -l`
        let pass_num=$pass_num+$pNum
        let fail_num=$fail_num+$fNum
        let block_num=$block_num+$bNum
        echo "------ numbers: $pass_num, $fail_num, $block_num --------"
     fi
done
let total_num=$pass_num+$fail_num+$block_num
let run_num=$pass_num+$fail_num

if [ $total_num -le 0 ];then
    echo "error: total test number low than 0" 
    exit 1
fi

run_rate=$(awk BEGIN'{r='$run_num'/'$total_num'*100;printf "%.0f\n", r}')
pass_rate_total=$(awk BEGIN'{r='$pass_num'/'$total_num'*100;printf "%.0f\n", r}')
pass_rate_exe=$(awk BEGIN'{r='$pass_num'/'$run_num'*100;printf "%.0f\n", r}')

run_rate=${run_rate%.*}
pass_rate_total=${pass_rate_total%.*}
pass_rate_exe=${pass_rate_exe%.*}

echo "run rate:$run_rate"
echo "pass_rate_total:$pass_rate_total"
echo "pass_rate_exe:$pass_rate_exe"
echo $report_site
echo $report_site | sed -e 's/\//\\\//g' -e "s/\?/\\\?/g" > tmp.txt
report_site=`cat tmp.txt`
rm -rf tmp.txt

#modify template report
ivi_report () {
   cp -f $TEMPLATE_REPORT $tmpreport
   sync
   sed -i -e "s/_image_tested/$image_date/g" -e "s/_Total_num/$total_num/g" -e "s/_Pass_num/$pass_num/g" \
   -e "s/_Fail_num/$fail_num/g" -e "s/_Blocked_num/$block_num/g" $tmpreport
   
   #get the attachments and sort the case result in xml file into case_tmp
   attach=""
   dmesgFile=""
   if [ -f "$tmpCase" ];then
       rm -rf $tmpCase
   fi
   
   size_check=""
   installed_size=`cat /tmp/$recipe/pkg-install/installed-size | sed "s/M//g"`
   
   echo "Generic++++Install on device ----PASS" >> $tmpCase
   echo "Generic++++Boot to multi-user mode ----PASS" >> $tmpCase
   echo "Generic++++installed-size on rootfs ----${installed_size}MB" >> $tmpCase
   
   for file in ${array[@]}
   do
      attach=$attach" "$file
      if echo "$file" | grep "dmesg_$image_date.log";then
          if [ -e "$dmesg_$image_date.log.gz" ];then
              rm -f "$dmesg_$image_date.log.gz"
          fi
          gzip "$file"
          sync
          dmesgFile="$file.gz"
      fi
      if echo "$file" |grep "\.result\.xml";then
          cat "$file" |grep purpose | grep result | grep auto | \
          sed "s/^.* component=\"//g" | sed  "s/\".*purpose=\"/++++/g" | \
          sed "s/\".*result=\"/----/g" | sed "s/\".*$//g" >> $tmpCase
      fi
   done
   
   echo $attach
   echo "-------------"
   echo $address
   echo "-------------"
   echo $image_date
   echo "-------------"
   
   redFail () {
   echo "$1" | sed "s/FAIL/<span style=\"color:red\">FAIL<\/span>/g" 
   }
   #format echo the test result and append the output into the template report
   line=`wc -l $tmpCase| awk '{print $1}'`
   cout=1
   pre_flag="Generic"
   failCase=""
   pre="&nbsp&nbsp&nbsp&nbsp"
   wd="100px"
   echo "<table border='0' align='left'>" >> $tmpreport
   echo "<tr>" >> $tmpreport
   echo "<td>$pre_flag</td>" >> $tmpreport
   echo "</tr>" >> $tmpreport
   while [ $cout -le $line ]
   do
      component=`sed -n "${cout}p" $tmpCase | sed "s/++++.*$//g"`
      purpose=`sed -n "${cout}p" $tmpCase|sed "s/^.*++++//g"| sed "s/----.*$//g" | \
               sed "s/^Check if//g"|sed "s/^To check if//g"|sed "s/^\s*//g"`
      result=`sed -n "${cout}p" $tmpCase |sed "s/^.*----//g"`
      if [ "$result" = "FAIL" ];then
          failCase=`echo $purpose | awk '{print $1}'`
      fi
      result=`redFail "$result"`
   
      if [ "$component" = "$pre_flag" ];then
          echo "<tr>" >> $tmpreport
          echo "<td width=$wd align='left'>$pre$purpose</td>" >> $tmpreport
          echo "<td width=$wd align='right'>$result</td>" >> $tmpreport
          echo "</tr>" >> $tmpreport
      else
          echo "<tr>" >> $tmpreport
          echo "<td>$component:</td>" >> $tmpreport
          echo "</tr>" >> $tmpreport
          echo "<tr>" >> $tmpreport
          echo "<td width=$wd align='left'>$pre$purpose</td>" >> $tmpreport
          echo "<td width=$wd align='right'>$result</td>" >> $tmpreport
          echo "</tr>" >> $tmpreport
          pre_flag="$component"
      fi
   
      let cout+=1
   done
   total_num=`expr $total_num + 2`
   pass_num=`expr $pass_num + 2`
   
   statistic(){
   
       echo "</tr>" >> $1
       echo "<tr>" >> $1
       if [ $fail_num -ne 0 ];then
           echo "<tr>" >> $1
           if [ -e "$dmesgFile" ];then
               echo "<td style='align:left' width=300px >dmesg log is attached for your reference.</td>" >> $1
           else
               echo "<td style='align:left' width=300px >dmesg log is not found.</td>" >> $1
           fi
           echo "</tr>" >> $1
       fi
       echo "<td style='align:left'>Total: $total_num</td>" >> $1
       echo "</tr>" >> $1
       echo "<tr>" >> $1
       echo "<td style='align:left'>Pass: $pass_num</td>" >> $1
       echo "</tr>" >> $1
       echo "<tr>" >> $1
       echo "<td style='align:left'>Fail: $fail_num</td>" >> $1
       echo "</tr>" >> $1
       echo "</table>"
       echo "</body>" >> $1
       echo "</html>" >> $1
   }
   
   
   rm -rf ~/sent   
   #send mail
   if [ $fail_num -eq 1 ];then
       plus="- FAIL-$failCase"
   elif [ $fail_num -gt 1 ];then
       plus="- Multiple_Failures"
   else
       plus="- PASS"
   fi
   echo "sending mail...."
   i=0
   statistic "$tmpreport"
   while true
   do
       if [ $fail_num -eq 0 ];then
          cat $tmpreport | mutt -e "set content_type=text/html" $address -s "$SUBJECT$image_date $plus"
          rtn=$?
       else
          if [ -e "$dmesgFile" ];then
              cat $tmpreport | mutt -e "set content_type=text/html" $address -s "$SUBJECT$image_date $plus" -a "$dmesgFile"
              rtn=$?
          else
              cat $tmpreport | mutt -e "set content_type=text/html" $address -s "$SUBJECT$image_date $plus"
              rtn=$?
          fi
       fi
       if [ $rtn -ne 0 ];then
           echo "the $i time(s) to try send fail"
           let i+=1
       else
           echo "mail sent"
           break
       fi
       if [ $i -ge $TIMES_SEND_MAIL ];then
           echo " $TIMES_SEND_MAIL times out"
           break
       fi
       sleep 10
   done
   i=0
   rst=`sh /opt/acceptance/date/ivi/deltaProcess.sh /opt/acceptance/data/previous-cases $tmpCase $tmpreport $imagePrefixName $image_date`
   if [ "$rst" = "diffFound" ];then
       plus=" diff with previous"
       while true
       do
           if [ $fail_num -eq 0 ];then
               cat $tmpreport | mutt -e "set content_type=text/html" $addresserror -s "$SUBJECT$image_date $plus"
               rtn=$?
           else
               cat $tmpreport | mutt -e "set content_type=text/html" $addresserror -s "$SUBJECT$image_date $plus" -a "$dmesgFile"
                rtn=$?
                 fi
                  if [ $rtn -ne 0 ];then
                      echo "the $i time(s) to try send fail"
                       let i+=1
                   else
                       echo "mail sent"
                       break
                   fi
                   if [ $i -ge $TIMES_SEND_MAIL ];then
                       echo " $TIMES_SEND_MAIL times out"
                       break
                   fi
                   sleep 10
               done
           fi
   mv $tmpreport /opt/2.0-automation/data/ivi-previous-report
   mv $tmpCase /opt/2.0-automation/data/ivi-previous-cases
}

pr3_report () {
   #modify template report
   if [ $Pass_rate_total == 100 ];then
   cp -f $TEMPLATE_PASS $tmpreport
   else
   cp -f $TEMPLATE_COMPLETED $tmpreport
   fi
   
   sed -i -e "s/_report_address/$report_site/g" -e "s/_image_tested/$image_date/g" -e "s/_recipe_id/$recipe/g" \
          -e "s/_Total_num/$total_num/g" -e "s/_Pass_num/$pass_num/g" -e "s/_Fail_num/$fail_num/g" \
          -e "s/_Blocked_num/$block_num/g" -e "s/_Run_rate/$run_rate/g" -e "s/_rate_total/$pass_rate_total/g" \
          -e "s/_rate_exe/$pass_rate_exe/g" $tmpreport
   
   #get the attachments and sort the case result in xml file into case_tmp
   attach=""
   if [ -f case_tmp ];then
       rm -rf case_tmp
   fi
   
   if [ -f $tmpCase ];then
       rm -rf $tmpCase
   fi
   
   :<<MULTILINECOMMENT
   wayland_install=`cat /tmp/$recipe/system-reboot/wayland-install`
   if [ $wayland_install == "0" ];then
       wayland="PASS"
       let pass_num+=1
   else
       wayland="FAIL"
       let fail_num+=1
   fi 
   
   let total_num+=1
MULTILINECOMMENT
   
   pass_num=`expr $pass_num + 2`
   echo "Total: $total_num; Fail: $fail_num; Pass Rate:$pass_rate_total%" >> $tmpreport
   echo "" >> $tmpreport
   echo "Key check points:" >> $tmpreport
   echo "---------------------------------------------------------------------" >> $tmpreport 
   echo "Acceptance/Generic:" >> $tmpreport
   echo "    Install on device                                                 PASS" >> $tmpreport
   echo "    Boot to multi-user mode                                           PASS" >> $tmpreport
   echo "PNP/Generic:" >> $tmpreport
   #cpuvalue=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | grep -i "value" | grep -i "cpu" |awk -F'"' '{print $14}'`
   #echo "    CPU usage during system idle:                                     $cpuvalue% " >> $tmpreport
   memvalue=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
             grep -i "value" | grep -i "mem_system_idle" |awk -F'"' '{print $14}'`
   memblank=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
             grep -i "value" | grep -i "mem_app_blank" |awk -F'"' '{print $14}'`
   warmsettings=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
                 grep -i "value" | grep -i "warm_time_app_settings" |awk -F'"' '{print $14}'`
   warmbrowser=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
                grep -i "value" | grep -i "warm_time_app_browser" |awk -F'"' '{print $14}'`
   a=`echo $memvalue | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
   b=`echo $memblank | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
   c=`echo $warmsettings | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
   d=`echo $warmbrowser | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
   
   if [ $a == "BLOCK" ]; then
     echo "    Memory usage during system idle:                                  BLOCK "  >> $tmpreport
   else
     echo "    Memory usage during system idle:                                  $memvalue"M" "  >> $tmpreport
   fi
   
   if [ $b == "BLOCK" ];then
     echo "    Memory usage during Blank-app:                                    BLOCK " >> $tmpreport
   else
     echo "    Memory usage during Blank-app:                                    $memblank"M" " >> $tmpreport
   fi
   
   if [ $c == "BLOCK" ];then
     echo "    Warm time to launch Settings:                                     BLOCK " >> $tmpreport
   else
     echo "    Warm time to launch Settings:                                     $warmsettings"s" " >> $tmpreport
   fi
   
   if [ $d == "BLOCK" ];then
     echo "    Warm time to launch Browser:                                      BLOCK " >> $tmpreport
   else
     echo "    Warm time to launch Browser:                                      $warmbrowser"s" " >> $tmpreport
   fi
   
   echo "" >> $tmpreport
   echo "Fail Test Case:" >> $tmpreport
   echo "---------------------------------------------------------------------" >> $tmpreport
   
   
   for file in ${array[@]}
   do
      attach=$attach" "$file
      if echo $file |grep "\.result\.xml";then
        cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
        sed  "s/\".*purpose=\"/++++/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g"| \
        grep FAIL | sort >> case_tmp
   	sed -i '/pnp/d' case_tmp
        cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
        sed  "s/\".*purpose=\"/----/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g" | \
        sort >> $tmpCase
   	sed -i '/pnp/d' $tmpCase
      fi
   done
      cp case_tmp $dir/case_tmp
   
   echo $attach
   echo "-------------"
   echo $address
   echo "-------------"
   echo $image_date
   echo "-------------"
   
   #format echo the test result and append the output into the template report
   line=`wc -l case_tmp| awk '{print $1}'`
   cout=1
   
   while [ $cout -le $line ]
   do
      component=`sed -n "${cout}p" case_tmp | sed "s/++++.*$//g"`
      purpose=`sed -n "${cout}p" case_tmp|sed "s/^.*++++//g"| sed "s/----.*$//g" | \
               sed "s/^Check if//g"|sed "s/^To check if//g"|sed "s/^\s*//g"`
      result=`sed -n "${cout}p" case_tmp |sed "s/^.*----//g"`
      if [ ${#purpose} -gt $MAX_LEN ];then
          tmp=`expr $MAX_LEN - 3`
          purpose=${purpose:0:$tmp}
      fi
      addition=''
      if [ ${#purpose} -lt $MAX_LEN ];then
          i=0
          dalt=`expr $MAX_LEN - ${#purpose}`
          while [ $i -lt $dalt ]
          do
              addition="$addition"" "
              let i+=1
          done
      fi
   
      purpose="$purpose$addition"
      if [ $component = $pre_flag ];then
          echo "    $purpose$result"|tee -a $tmpreport
      else
          echo "$component:"|tee -a $tmpreport
          echo "    $purpose$result" |tee -a $tmpreport
          pre_flag="$component"
      fi
   
      let cout+=1
   done
   
   if [ $pass_rate_total == 100 ];then
   echo "No fail test case in this circle testing." >> $tmpreport
   fi
   echo "" >> $tmpreport
   
   ReportURL=`cat /tmp/running_bat.log | grep -i "http" | awk '{print $6}' | \
              sed "s/http:\/\/.*[0-9]\//https:\/\/tzqarpt.otcshare.org\//g"`
   sed -i "/^This/a Detail log files can be found in QA Report:'\ $ReportURL'" $tmpreport
   
   rm -rf ~/sent
   #send mail
   echo "sending mail...."
   if [ $pass_rate_total == 100 ];then
   cat $tmpreport | mutt $address -s "$SUBJECT $image_date PASS"  -a "$tmpCase"
   else
   cat $tmpreport | mutt $address -s "$SUBJECT $image_date - $pass_rate_total% Pass"  -a "$tmpCase"
   fi
   
   if [ $? -ne 0 ];then
       echo "send mail fail, reture value is $?"
   fi
   echo "mail sent !"
   rm -rf $tmpreport
   rm -rf case_tmp
}

lunchbox_test () { 
    #modify template report
    if [ $Pass_rate_total == 100 ];then
    cp -f $TEMPLATE_PASS $tmpreport
    else
    cp -f $TEMPLATE_COMPLETED $tmpreport
    fi
    
    sed -i -e "s/_report_address/$report_site/g" -e "s/_image_tested/$image_date/g" -e "s/_recipe_id/$recipe/g" \
           -e "s/_Total_num/$total_num/g" -e "s/_Pass_num/$pass_num/g" -e "s/_Fail_num/$fail_num/g" \
           -e "s/_Blocked_num/$block_num/g" -e "s/_Run_rate/$run_rate/g" -e "s/_rate_total/$pass_rate_total/g" \
           -e "s/_rate_exe/$pass_rate_exe/g" $tmpreport
    
    #get the attachments and sort the case result in xml file into case_tmp
    attach=""
    if [ -f case_tmp ];then
        rm -rf case_tmp
    fi
    
    if [ -f $tmpCase ];then
        rm -rf $tmpCase
    fi
    
    :<<MULTILINECOMMENT
    wayland_install=`cat /tmp/$recipe/system-reboot/wayland-install`
    if [ $wayland_install == "0" ];then
        wayland="PASS"
        let pass_num+=1
    else
        wayland="FAIL"
        let fail_num+=1
    fi 
    
    let total_num+=1
MULTILINECOMMENT
    
    pass_num=`expr $pass_num + 2`
    echo "Total: $total_num; Fail: $fail_num; Pass Rate:$pass_rate_total%" >> $tmpreport
    echo "" >> $tmpreport
    echo "Key check points:" >> $tmpreport
    echo "---------------------------------------------------------------------" >> $tmpreport 
    echo "Acceptance/Generic:" >> $tmpreport
    echo "    Install on device                                                 PASS" >> $tmpreport
    echo "    Boot to multi-user mode                                           PASS" >> $tmpreport
    echo "PNP/Generic:" >> $tmpreport
    #cpuvalue=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | grep -i "value" | grep -i "cpu" |awk -F'"' '{print $14}'`
    #echo "    CPU usage during system idle:                                     $cpuvalue% " >> $tmpreport
    memvalue=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
              grep -i "value" | grep -i "mem_system_idle" |awk -F'"' '{print $14}'`
    memblank=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
              grep -i "value" | grep -i "mem_app_blank" |awk -F'"' '{print $14}'`
    warmsettings=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
                  grep -i "value" | grep -i "warm_time_app_settings" |awk -F'"' '{print $14}'`
    warmbrowser=`cat /tmp/$recipe/pnp-acceptance-tests/pnp-acceptance-tests.result.xml | \
                 grep -i "value" | grep -i "warm_time_app_browser" |awk -F'"' '{print $14}'`
    a=`echo $memvalue | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
    b=`echo $memblank | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
    c=`echo $warmsettings | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
    d=`echo $warmbrowser | awk ' {if ($1 <= 0) print "BLOCK";else print "OK";}'`
    
    if [ $a == "BLOCK" ]; then
      echo "    Memory usage during system idle:                                  BLOCK "  >> $tmpreport
    else
      echo "    Memory usage during system idle:                                  $memvalue"M" "  >> $tmpreport
    fi
    
    if [ $b == "BLOCK" ];then
      echo "    Memory usage during Blank-app:                                    BLOCK " >> $tmpreport
    else
      echo "    Memory usage during Blank-app:                                    $memblank"M" " >> $tmpreport
    fi
    
    if [ $c == "BLOCK" ];then
      echo "    Warm time to launch Settings:                                     BLOCK " >> $tmpreport
    else
      echo "    Warm time to launch Settings:                                     $warmsettings"s" " >> $tmpreport
    fi
    
    if [ $d == "BLOCK" ];then
      echo "    Warm time to launch Browser:                                      BLOCK " >> $tmpreport
    else
      echo "    Warm time to launch Browser:                                      $warmbrowser"s" " >> $tmpreport
    fi
    
    echo "" >> $tmpreport
    echo "Fail Test Case:" >> $tmpreport
    echo "---------------------------------------------------------------------" >> $tmpreport
    
    
    for file in ${array[@]}
    do
       attach=$attach" "$file
       if echo $file |grep "\.result\.xml";then
          cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
          sed  "s/\".*purpose=\"/++++/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g"| \
          grep FAIL | sort >> case_tmp
    	  sed -i '/pnp/d' case_tmp
          cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
          sed  "s/\".*purpose=\"/----/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g" | \
          sort >> $tmpCase
    	  sed -i '/pnp/d' $tmpCase
       fi
    done
       cp case_tmp $dir/case_tmp
    
    echo $attach
    echo "-------------"
    echo $address
    echo "-------------"
    echo $image_date
    echo "-------------"
    
    #format echo the test result and append the output into the template report
    line=`wc -l case_tmp| awk '{print $1}'`
    cout=1
    
    while [ $cout -le $line ]
    do
       component=`sed -n "${cout}p" case_tmp | sed "s/++++.*$//g"`
       purpose=`sed -n "${cout}p" case_tmp|sed "s/^.*++++//g"| sed "s/----.*$//g" | \
                sed "s/^Check if//g"|sed "s/^To check if//g"|sed "s/^\s*//g"`
       result=`sed -n "${cout}p" case_tmp |sed "s/^.*----//g"`
       if [ ${#purpose} -gt $MAX_LEN ];then
           tmp=`expr $MAX_LEN - 3`
           purpose=${purpose:0:$tmp}
       fi
       addition=''
       if [ ${#purpose} -lt $MAX_LEN ];then
           i=0
           dalt=`expr $MAX_LEN - ${#purpose}`
           while [ $i -lt $dalt ]
           do
               addition="$addition"" "
               let i+=1
           done
       fi
    
       purpose="$purpose$addition"
       if [ $component = $pre_flag ];then
           echo "    $purpose$result"|tee -a $tmpreport
       else
           echo "$component:"|tee -a $tmpreport
           echo "    $purpose$result" |tee -a $tmpreport
           pre_flag="$component"
       fi
    
       let cout+=1
    done
    
    if [ $pass_rate_total == 100 ];then
    echo "No fail test case in this circle testing." >> $tmpreport
    fi
    echo "" >> $tmpreport
   
    ReportURL=`cat /tmp/running_bat.log | grep -i "http" | awk '{print $6}' | \
               sed "s/http:\/\/.*[0-9]\//https:\/\/qartq.tizendev.org\//g"` 
    echo "Full report: $ReportURL" >> $tmpreport
    rm -rf ~/sent
    #send mail
    echo "sending mail...."
    if [ $pass_rate_total == 100 ];then
    cat $tmpreport | mutt $address -s "$SUBJECT $image_date PASS"  -a "$tmpCase"
    else
    cat $tmpreport | mutt $address -s "$SUBJECT $image_date - $pass_rate_total% Pass"  -a "$tmpCase"
    fi
    
    if [ $? -ne 0 ];then
        echo "send mail fail, reture value is $?"
    fi
    echo "mail sent !"
    rm -rf $tmpreport
    rm -rf case_tmp
}

release_report () {
   #modify template report
   if [ -f report ]; then
       rm -rf report
   fi
   
   if [ $Pass_rate_total == 100 ];then
   cp -f $TEMPLATE_PASS report
   else
   cp -f $TEMPLATE_COMPLETED report
   fi
   
   sed -i -e "s/_report_address/$report_site/g" -e "s/_image_tested/$image_date/g" -e "s/_recipe_id/$recipe/g" \
          -e "s/_Total_num/$total_num/g" -e "s/_Pass_num/$pass_num/g" -e "s/_Fail_num/$fail_num/g" \
          -e "s/_Blocked_num/$block_num/g" -e "s/_Run_rate/$run_rate/g" -e "s/_rate_total/$pass_rate_total/g" \
          -e "s/_rate_exe/$pass_rate_exe/g" report
   
   sed -i '/^Latest/a '$newimage'' report
   
   #get the attachments and sort the case result in xml file into case_tmp
   attach=""
   if [ -f case_tmp ];then
      rm -rf case_tmp
   fi
   
   if [ -f /tmp/release_case_status.log ];then
      rm -rf /tmp/release_case_status.log
   fi
   
   :<<MULTILINECOMMENT
   wayland_install=`cat /tmp/$recipe/system-reboot/wayland-install`
   if [ $wayland_install == "0" ];then
      wayland="PASS"
      let pass_num+=1
   else
      wayland="FAIL"
      let fail_num+=1
   fi 
   
   let total_num+=1
MULTILINECOMMENT
   
   pass_num=`expr $pass_num + 2`
   if [ -f $REPORT_FILE ];then
     rm -rf $REPORT_FILE
   fi
   
   echo "" > $REPORT_FILE
   echo "" >> $REPORT_FILE
   echo "latest released image:Total: $total_num; Fail: $fail_num; Pass Rate:$pass_rate_total%" >> $REPORT_FILE
   echo "" >> /tmp/release_case_status.log
   echo "image:$newimage" >> /tmp/release_case_status.log
   echo "---------" >> /tmp/release_case_status.log
   
   echo $pass_rate_total > releaserate
   
   for file in ${array[@]}
   do
     attach=$attach" "$file
     if echo $file |grep "\.result\.xml";then
         cat $file |grep purpose | grep result | grep auto | \
         sed "s/^.* component=\"//g" | sed  "s/\".*purpose=\"/++++/g" | sed "s/\".*result=\"/----/g" | \
         sed "s/\".*$//g"| grep FAIL | sort >> case_tmp
         sed -i '/pnp/d' case_tmp
         cat $file |grep purpose | grep result | grep auto |  \
         sed "s/^.* component=\"//g" | sed  "s/\".*purpose=\"/----/g" | sed "s/\".*result=\"/----/g" | \
         sed "s/\".*$//g" | sort >> /tmp/release_case_status.log
         sed -i '/pnp/d' /tmp/release_case_status.log
     fi
   done
     cp /tmp/case_tmp $dir/case_tmp
   
   echo $attach
   echo "-------------"
   echo $address
   echo "-------------"
   echo $image_date
   echo "-------------"
   
   echo $image_date > releaseimagedate
   
   #format echo the test result and append the output into the template report
   line=`wc -l case_tmp| awk '{print $1}'`
   cout=1
   while [ $cout -le $line ]
   do
     component=`sed -n "${cout}p" case_tmp | sed "s/++++.*$//g"`
     purpose=`sed -n "${cout}p" case_tmp|sed "s/^.*++++//g"| sed "s/----.*$//g" | sed "s/^Check if//g"| \
              sed "s/^To check if//g"|sed "s/^\s*//g"`
     result=`sed -n "${cout}p" case_tmp |sed "s/^.*----//g"`
     if [ ${#purpose} -gt $MAX_LEN ];then
         tmp=`expr $MAX_LEN - 3`
         purpose=${purpose:0:$tmp}
     fi
     addition=''
     if [ ${#purpose} -lt $MAX_LEN ];then
         i=0
         dalt=`expr $MAX_LEN - ${#purpose}`
         while [ $i -lt $dalt ]
         do
             addition="$addition"" "
             let i+=1
         done
     fi
     let cout+=1
   done
   rm -rf ~/sent
   }

prerelease_report () {
   attach=""
   if [ -f case_tmp ];then
       rm -rf case_tmp
   fi
   
   :<<MULTILINECOMMENT
   wayland_install=`cat /tmp/$recipe/system-reboot/wayland-install`
   if [ $wayland_install == "0" ];then
       wayland="PASS"
       let pass_num+=1
   else
       wayland="FAIL"
       let fail_num+=1
   fi 
   
   let total_num+=1
MULTILINECOMMENT
   
   pass_num=`expr $pass_num + 2`
   echo "" >> /tmp/pre_case_status.log
   echo "image:$newimage" >> /tmp/pre_case_status.log
   echo "---------" >> /tmp/pre_case_status.log
   
   for file in ${array[@]}
   do
      attach=$attach" "$file
      if echo $file |grep "\.result\.xml";then
         cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
         sed  "s/\".*purpose=\"/++++/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g"| \
         grep FAIL | sort >> case_tmp
         sed -i '/pnp/d' case_tmp
         cat $file |grep purpose | grep result | grep auto | sed "s/^.* component=\"//g" | \
         sed  "s/\".*purpose=\"/----/g" | sed "s/\".*result=\"/----/g" |sed "s/\".*$//g" | \
         sort >> /tmp/pre_case_status.log
         sed -i '/pnp/d' /tmp/pre_case_status.log
      fi
   done
      cp /tmp/case_tmp $dir/case_tmp
   
   echo $attach
   echo "-------------"
   echo $address
   echo "-------------"
   echo $image_date
   echo "-------------"
   
   #format echo the test result and append the output into the template report
   line=`wc -l case_tmp| awk '{print $1}'`
   cout=1
   
   while [ $cout -le $line ]
   do
      component=`sed -n "${cout}p" case_tmp | sed "s/++++.*$//g"`
      purpose=`sed -n "${cout}p" case_tmp|sed "s/^.*++++//g"| sed "s/----.*$//g" | \
               sed "s/^Check if//g"|sed "s/^To check if//g"|sed "s/^\s*//g"`
      result=`sed -n "${cout}p" case_tmp |sed "s/^.*----//g"`
      if [ ${#purpose} -gt $MAX_LEN ];then
          tmp=`expr $MAX_LEN - 3`
          purpose=${purpose:0:$tmp}
      fi
      addition=''
      if [ ${#purpose} -lt $MAX_LEN ];then
          i=0
          dalt=`expr $MAX_LEN - ${#purpose}`
          while [ $i -lt $dalt ]
          do
              addition="$addition"" "
              let i+=1
          done
      fi
      purpose="$purpose$addition"
      let cout+=1
   done
   ReportURL=`cat /tmp/running_bat.log | grep -i "http" | awk '{print $6}' | sed "s/http:\/\/.*[0-9]\//https:\/\/tzqarpt.otcshare.org\//g"`
   
   sed -i "/^This/a Detail Pre-Release image log files can be found in QA Report:'\ $ReportURL'" report
   rm -rf ~/sent
   
   echo "pre-release image:Total: $total_num; Fail: $fail_num; Pass Rate:$pass_rate_total%" >> $REPORT_FILE
   
   #diff
   check_report_available () {
      REPORT_DIR=$1
      FILE_PATTERN=$2
      NUM_REPORTS=`ls $REPORT_DIR/*/*.$FILE_PATTERN 2>/dev/null | wc -l`
      if [[ $NUM_REPORTS -eq 0 ]]
      then
         return 1
      else
         return 0
      fi
   }
   
   generate_test_report_diff () {
      REF_REPORT_DIR=`cat diffnumb`
      #UPDATED_REPORT_DIR=$2
      CACHEDIR="/opt/pre-pretrunk-autotest/data/tizen-dev-testing/"
      # REPORT_FILE="/opt/pre-pretrunk-autotest/data/tizen-dev-testing/REPORT.log"
      TMP_FILE_REF_RECORD="$CACHEDIR/tmpfile_ref_rec"
      TMP_FILE_UPDATED_RECORD="$CACHEDIR/tmpfile_updated_rec"
   
      mkdir -p $CACHEDIR
      touch $CACHEDIR/tmpfile_ref_rec
      touch $CACHEDIR/tmpfile_updated_rec
      #touch $REPORT_FILE
   
      #echo $newimage |awk '/tizen-/{print $10}' >>$REPORT_FILE
      # Ensure the test reports are ready before starting analysis.
      check_report_available "/tmp/$REF_REPORT_DIR" "xml"
      ref_report_valid=$?
      if [ ! $ref_report_valid -eq 0 ]
      then
         echo -e "\nError! PRETest report against reference image is invalid!"
         return 1
      fi
   
      check_report_available "/tmp/$UPDATED_REPORT_DIR" "xml"
      updated_report_valid=$?
   
      if [ ! $updated_report_valid -eq 0 ]
   then
         echo -e "\nError! PRETest report against updated image is invalid!"
         return 1
      fi
   
      TOTAL=`cat "/tmp/$UPDATED_REPORT_DIR"/*/*.xml | \
             grep "testcase.*component" | wc -l`
   
      # Avoid the divided by zero error.
      if [[ $TOTAL -eq 0 ]]
      then
         TOTAL=1
      fi
   
      PASSED=`cat "/tmp/$UPDATED_REPORT_DIR"/*/*.xml | \
              grep "testcase.*component" | grep "PASS" | wc -l`
   
      FAILED=`cat "/tmp/$UPDATED_REPORT_DIR"/*/*.xml | \
              grep "testcase.*component" | grep "FAIL" | wc -l`
   
      RATE_PASSED=`awk 'BEGIN{printf "%.2f%%\n",('$PASSED'/'$TOTAL')*100}'`
      RATE_FAILED=`awk 'BEGIN{printf "%.2f%%\n",('$FAILED'/'$TOTAL')*100}'`
   
      cat "/tmp/$REF_REPORT_DIR"/*/*.xml | \
           grep "testcase.*component" | \
           sed 's/.*result=\"\([^\"]*\)\".*/\"\1\"\.SEP\. \0/g' | \
           sed 's/.*id=\"\([^\"]*\)\".*/\"\1\" \0/g' | \
           sed 's/.*component=\"\([^\"]*\)\".*/\"\1\" \0/g' | \
           sed 's/\(.*\)\.SEP\..*/\1/g' | sort > $TMP_FILE_REF_RECORD
   
      cat "/tmp/$UPDATED_REPORT_DIR"/*/*.xml | \
           grep "testcase.*component" | \
           sed 's/.*result=\"\([^\"]*\)\".*/\"\1\"\.SEP\. \0/g' | \
           sed 's/.*id=\"\([^\"]*\)\".*/\"\1\" \0/g' | \
           sed 's/.*component=\"\([^\"]*\)\".*/\"\1\" \0/g' | \
           sed 's/\(.*\)\.SEP\..*/\1/g' | sort > $TMP_FILE_UPDATED_RECORD
   
   
       awk -F\" '
           BEGIN  {
              file_seq=0 }
   
           FILENAME != lastfile  { 
              lastfile = FILENAME
              file_seq++
           }
   
           # Section for each line
           {
              arrkey="Component: "$2", Test_Case: "$4
              if (file_seq == 1) {
                 resultarr[arrkey] = $6
              }
              if (file_seq == 2) {
                 resultarr[arrkey] = resultarr[arrkey]"-"$6
              }
           }
           END  {
              numregfailure=0
              numregrunable=0
              numimppass=0
              numimprunable=0
              for (rec in resultarr)
              {
                 numitm = split (resultarr[rec], result, "-")
                 first_char = substr(resultarr[rec],1,1)
                 if (numitm > 0)
                {
                    res_ref=-1
                    res_updated=-1
                    if (numitm == 2 && first_char != "-") {
                       if (result[1] != result[2]) {
                          if (result[1] == "PASS") {
                             regfailure[numregfailure]=rec
                             numregfailure++ 
                          }
                          else {
                             imppass[numimppass]=rec
                             numimppass++
                          }
                       }
                    }
                    else {
                       if (first_char == "-") {
                          imprunable[numimprunable]=rec
                          numimprunable++
                       }
                       else {
                          regrunable[numregrunable]=rec
                          numregrunable++
                       }
                    }
                 }
              }
              print "\nImprovements:"
              printf "Fail -> Pass  Number: %d\n", numimppass
              if (numimppass > 0) {
                 for (i=0; i<numimppass; i++) {
                    print imppass[i]
                 }
              }
              printf "Not Runable -> Runable  Number: %d\n", numimprunable
              if (numimprunable > 0) {
                 for (i=0; i<numimprunable; i++) {
                    print imprunable[i]
                 }
              }
              printf "Pass -> Fail  Number: %d\n", numregfailure
              if (numregfailure > 0) {
                 for (i=0; i<numregfailure; i++) {
                    print regfailure[i]
                 }
              }
              printf "Runable -> Not Runable  Number: %d\n", numregrunable
              if (numregrunable > 0) {
                 for (i=0; i<numregrunable; i++) {
                    print regrunable[i]
                 }
              }
           }
           ' "$TMP_FILE_REF_RECORD" "$TMP_FILE_UPDATED_RECORD" >>$REPORT_FILE
   }
   
   echo $newimage |awk -F/ '/tizen-/{print $8}'
   echo "" >>$REPORT_FILE
   imageid=`echo $newimage |awk -F/ '/tizen-/{print $8}'`
   generate_test_report_diff
   echo $UPDATED_REPORT_DIR
   echo $REF_REPORT_DIR
   
   #sort report
   cat $REPORT_FILE | sed -n '/^Fail\ \-/,/^Not\ R/p' | grep Component | sort > difftest1
   cat $REPORT_FILE | sed -n '/^Not\ Runa/,/^Regressions/p' | grep Component | sort > difftest2
   cat $REPORT_FILE | sed -n '/^Regressions/,/^Runable/p' | grep Component | sort > difftest3
   cat $REPORT_FILE | sed -n '/^Runable/,$p' | grep Component | sort > difftest4
   
   sed -i '/^Component/d' $REPORT_FILE
   sed -i '/^Fail\ \-/r  difftest1' $REPORT_FILE
   sed -i '/^Not\ Runable/r difftest2' $REPORT_FILE
   sed -i '/^Pass\ \-/r difftest3' $REPORT_FILE
   sed -i '/^Runable/r difftest4' $REPORT_FILE
   
   COMPARE=`diff_build $PRECHACHEF $PRECURF`
   
   #send mail
   
   cat $REPORT_FILE >> report
   
   ##diffpackage
   releaseimagedate=`cat releaseimagedate`
   
   echo "Changed packages list for reference:" > /tmp/diffpackage.log
   
   timeout 180 wget https://download.tz.otcshare.org/testing/trunk/mobile/tizen-mobile-staging_$image_date/builddata/reports/repodiff-tizen-mobile_$releaseimagedate--tizen-mobile-staging_$image_date.html --user=$USER --password=$PASSWORD
   
   cat repodiff-tizen-mobile_$releaseimagedate--tizen-mobile-staging_$image_date.html | grep search_text | \
        awk -F\> '{print $3}' | sed "s/<\/a//g" | sed "s/<br//g" | sed '/^$/d' >> /tmp/diffpackage.log
   
   echo "" >> report
   echo "Package change log put in attachment" >> report
   
   releaserate=`cat releaserate`
   grade=$[ pass_rate_total - releaserate ]
   
   o "sending mail...."
   if [ $releaserate -gt $pass_rate_total ];then
   cat report | mutt $address -s "$SUBJECT--$image_datei -- upgrade $grade%"  -a "/tmp/release_case_status.log" -a "/tmp/pre_case_status.log" -a "/tmp/diffpackage.log"
   elif [ $pass_rate_total == $releaserate ];then
   cat report | mutt $address -s "$SUBJECT--$image_date -- same result "  -a "/tmp/release_case_status.log" -a "/tmp/pre_case_status.log" -a "/tmp/diffpackage.log"
   elif [ $pass_rate_total -lt $releaserate ];then
   cat report | mutt $address -s "$SUBJECT--$image_date -- downgrade $grade%"  -a "/tmp/release_case_status.log" -a "/tmp/pre_case_status.log" -a "/tmp/diffpackage.log"
   else
   cat report | mutt $address -s "$SUBJECT--$image_date "  -a "/tmp/release_case_status.log" -a "/tmp/pre_case_status.log" -a "/tmp/diffpackage.log"
   fi
   
   sed -i '/^Pre-Release\ image\:/{p;:a;N;$!ba;d}' report
   sed -i '/^Detail\ Pre-Release\ image/d' report
   
   if [ $? -ne 0 ];then
       echo "send mail fail, reture value is $?"
   fi
   echo "mail sent !"
   rm -rf report1
   rm -rf case_tmp
   sed -i '/^pre-release\ image\:/,$d' $REPORT_FILE
}

if echo $newimage | grep "ivi";then 
   ivi_report
elif echo $newimage | grep "handset-blackbay-tizen-mobile_";then
   pr3_report
elif echo $newimage | grep 
   release_report
elif echo $newimage | grep "staging_";then
   prerelease_report
else 
   echo "test fail"
   exit 1
fi


    

