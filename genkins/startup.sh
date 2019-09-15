# 杀死久进程
pid = `ps -ef | grep myApp.jar | grep -v | grep | awk 'print $2'`
if [-n "$pid"]
then
	kill -9 $pid
	echo $pid "has been killed"
fi

nohup java -server -XX:+useG1GC -jar -spring.profiles.active=dev -Dport=8081 myApp.jar &