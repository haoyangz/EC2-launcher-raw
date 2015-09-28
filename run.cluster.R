
############
# functions

rsystem <- function(sh,intern=F,wait=T){
	    system(paste0('ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ',starcluster.rsa,' ubuntu@',INSTANCE_NAME,' ',shQuote(sh)),intern=intern,wait=wait)
}

scptoclus <- function(infile,out,intern=F){
	    system(paste0('scp -r -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' ',shQuote(infile),' ubuntu@',INSTANCE_NAME,':',shQuote(out)))
}

scpstring <- function(infile,out,intern=F){
	    paste0('scp -r -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' ',shQuote(infile),' ubuntu@',INSTANCE_NAME,':',shQuote(out))
}

scpfromclus <- function(infile,out,intern=F){
	    system(paste0('scp -r -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' -r ubuntu@',INSTANCE_NAME,':',shQuote(infile),' ',shQuote(out)))
}

getFilename<-function(x){
	    rev(strsplit(x,'/')[[1]])[1]
}

#######################
## Param preparation
#######################

t1=Sys.time()

options(echo=TRUE)

args = commandArgs(T)
paramfile = args[1]
runstrfile = args[2]

### Load the params
param=readLines(paramfile)
if (length(grep('#',param))>0) param=param[-grep('#',param)]
for(sp in strsplit(param,'\\s+')){
	print(sp)
    assign(sp[1],sp[2])
}

### Load the runstr
runstr = readLines(runstrfile)
runstr = runstr[runstr!='']
pick = grep('#',runstr)
if (length(pick)>0) runstr = runstr[-pick]
runstr = paste(runstr,collapse=';')
print('String to run:')
print(runstr)

### Load credential file
print('parse credential file')
cf=readLines(cred.file)
cf=cf[-grep('#',cf)]
for(sp in strsplit(cf,':')){
	print(sp)
    assign(sp[1],sp[2])
}
if(!file.exists(rsa_key)){print('check rsa key is readable')}
keyname=rev(strsplit(rsa_key,'[/.]')[[1]])[2]

tmp = paste0(tempfile(),'.rsa')
file.copy(rsa_key,tmp)
Sys.chmod(tmp,mode='600')
rsa_key = tmp

#set up credentials
starcluster.rsa = rsa_key
access.key = access_key
secret.key = secret_key

########################
## Launch the instance
########################

print('Starting experiment:')
##launch instance
userdatablob=paste0(system('cat user-data.txt | base64',intern=T),collapse='')
lspec = paste0("\'{\"UserData\":\"",userdatablob,"\",\"ImageId\":\"",ami,"\",\"KeyName\":\"",keyname,"\",\"InstanceType\":\"",itype,"\"}\'")
launch=system(paste0('aws --region ',realm,' --output text ec2 request-spot-instances --spot-price ',price,' --launch-specification ',lspec),intern=T)

sirname = strsplit(launch,'\t')[[1]][4]
sistatus = ''

## check if spot is up
print('wait for spot fulfilment')
while(sistatus!='fulfilled'){
	cat('.')
    tryCatch({
		sitest=system(paste0('aws --region ',realm,' --output text ec2 describe-spot-instance-requests --spot-instance-request-ids ',sirname),intern=T)
		sistatus=strsplit(sitest,'\t')[[grep('STATUS',sitest)]][2]
	}, error = function(e){
					print(e)
					Sys.sleep(10)
	})
	Sys.sleep(5)
}
iname = strsplit(sitest,'\t')[[1]][3]

rname=paste0(exptname,postfix)
system(paste0('aws --region ',realm,' --output text ec2 create-tags --resources ',iname,' --tags Key=Name,Value=',rname))

istatus = 'initializing'
checks.passed = 0

print('wait for status checks')
while(checks.passed < 2){
	cat('.')
    tryCatch({
		itest=system(paste0('aws --region ',realm,' --output text ec2 describe-instance-status --instance-ids ',iname),intern=T)
		if(length(itest)>=3){
			checks.passed = length(grep('passed',itest))
		}
	}, error = function(e){
			print(e)
			Sys.sleep(10)
	})
	Sys.sleep(5)
}

istat=system(paste0('aws --region ',realm,' --output text ec2 describe-instances --instance-ids ',iname),intern=T)
INSTANCE_NAME = strsplit(istat,'\t')[[grep('INSTANCES',istat)]][16]

## Wait until all user-data are executed
while(length(grep('done',rsystem('ls /mnt',intern=T)))==0) { Sys.sleep(5) }
while(length(grep('done',rsystem('ls /home/ubuntu',intern=T)))==0) { Sys.sleep(5) }

## Move script and data
print('Moving data')
scptoclus(datadir,'/mnt/input/')

## Enable credentials remotely
print('Enable cred remotely')
rsystem('mkdir ~/.aws')
rsystem(paste0('printf \"[default]\naws_access_key_id=',access.key,'\naws_secret_access_key=',secret.key,'\" > ~/.aws/config'))

## Upload running sequence
print('Start running')

rl=readLines('template.txt')
rl=gsub('RUN_NAME',rname,rl)
rl=gsub('REGION',realm,rl)
rl=gsub('SIRNAME',sirname,rl)
rl=gsub('INAME',iname,rl)
rl=gsub('EMAIL',mailaddr,rl)
rl=gsub('RUN_STR',runstr,rl)
rl=gsub('BUCKET_NAME',bucket_name,rl)

rsystem(paste0('printf \'',paste0(rl,collapse='\n'),'\' > ~/runall.sh'))
rsystem('chmod +x ~/runall.sh')
rsystem('nohup ~/runall.sh `</dev/null` >nohup.txt 2>&1 &')
print('Launch finished in:')
print(Sys.time()-t1)
