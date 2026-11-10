#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fail() { echo "Development safety check: $*" >&2; exit 1; }
[[ ${DOCKER_HOST:-unix:///var/run/docker.sock} == unix:///var/run/docker.sock ]] || fail 'remote Docker host'
[[ -z ${DOCKER_CONTEXT:-} || ${DOCKER_CONTEXT} == default ]] || fail 'non-default Docker context'
[[ -z ${DOCKER_TLS_VERIFY:-}${DOCKER_CERT_PATH:-}${DOCKER_TLS:-} ]] || fail 'Docker TLS selectors supplied'
project=${CODEX_DEV_PROJECT:-fullstack-codex-dev}
[[ $project =~ ^fullstack-codex-dev(-[a-z0-9]+)*$ ]] || fail 'invalid development project'
frontend_port=${CODEX_DEV_FRONTEND_PORT-3000}
[[ $frontend_port =~ ^[1-9][0-9]{3,4}$ ]] && (( frontend_port >= 1024 && frontend_port <= 65535 )) || fail 'frontend host port must be a canonical integer from 1024 to 65535'
sha=$(git rev-parse HEAD)
ca=${CODEX_PROXY_CERT:-/etc/ssl/certs/ca-certificates.crt}
[[ -f $ca && -r $ca ]] || fail 'unreadable proxy CA'
# Only a public PEM certificate bundle may enter the build; never private keys.
[[ $(head -n 1 "$ca") == '-----BEGIN CERTIFICATE-----' ]] || fail 'CA must be PEM certificates'
cert_status=0
rg -q 'PRIVATE KEY' "$ca" || cert_status=$?
[[ $cert_status == 1 ]] || fail 'private key in CA input or certificate scan failed'
# env -i excludes production credentials and Compose selectors; Docker config is
# retained for the platform build proxy configuration. Never dump its contents.
buildx_config=""
docker_local() {
 env -i HTTP_PROXY="${HTTP_PROXY:-}" HTTPS_PROXY="${HTTPS_PROXY:-}" NO_PROXY="${NO_PROXY:-}" http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" BUILDX_CONFIG="$buildx_config" PATH="$PATH" HOME="$HOME" DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}" \
 CODEX_DEV_PROJECT="$project" CODEX_DEV_FRONTEND_PORT="$frontend_port" CODEX_DEV_SHA="$sha" CODEX_DEV_CA="$ca" \
 docker --host=unix:///var/run/docker.sock "$@"
}
version=$(docker_local compose version --short)
python3 - "$version" <<'PY'
import re,sys
v=tuple(map(int,re.findall(r'\d+',sys.argv[1])[:3]))
if v < (2,24,4): raise SystemExit('Development safety check: Compose >=2.24.4 required')
PY
docker_local info --format '{{.OSType}}/{{.Architecture}}' >/dev/null
compose() { docker_local compose --project-name "$project" --project-directory "$root" --env-file "$root/dev/local.env" -f "$root/docker-compose.yml" -f "$root/dev/compose.override.yml" "$@"; }
# Validate all resources before every command, including builds and startup.
rendered=$(compose config --format json)
validation_code=$(cat <<'PYVALIDATE'
import json,sys,pathlib,copy
root=pathlib.Path(sys.argv[1]); p=sys.argv[2]; sha=sys.argv[3]; ca=sys.argv[4]; host_port=sys.argv[5]; mode=sys.argv[6]
def check(ok,msg):
 if not ok: raise SystemExit("Development safety check: "+msg)

def keys(v,allowed,label):
 check(isinstance(v,dict) and set(v)<=set(allowed),label+" unexpected keys")
def strict(c):
 keys(c,["name","services","volumes","networks","secrets"],"model")
 check(c.get("name")==p,"project name")
 for name,s in c.get("services",{}).items():
  allowed=["container_name","image","platform","restart","environment","volumes","networks","ports","healthcheck","depends_on","command","entrypoint"]
  keys(s,allowed+(["build"] if name!="mysql" else []),name)
  for port in s.get("ports",[]):keys(port,["mode","host_ip","target","published","protocol"],"port")
  for m in s.get("volumes",[]):
   keys(m,["type","source","target","read_only","bind","volume"],"mount")
   if "bind" in m:keys(m["bind"],["create_host_path"],"bind")
   if m.get("type")=="bind":
    source=pathlib.Path(m["source"])
    check(source.is_file() and not source.is_symlink() and source.resolve()==source,"unsafe or missing bind source")
   if "volume" in m:check(m["volume"]=={},"volume mount options")
  if "build" in s:
   keys(s["build"],["context","dockerfile","secrets","labels"],"build")
   check(s["build"].get("labels")=={"org.opencontainers.image.revision":sha},"build labels")
  deps={} if name=="mysql" else {("mysql" if name=="backend" else "backend"):{"condition":"service_healthy","required":True}}
  check(s.get("depends_on",{})==deps,"dependency ordering")
  h=s.get("healthcheck",{});keys(h,["test","interval","timeout","retries","start_period"],"healthcheck")
  tests={
   "mysql":["CMD-SHELL",'MYSQL_PWD=$$MYSQL_PASSWORD mysql -h 127.0.0.1 -u dev_app fullstack -e "SELECT id FROM users LIMIT 1"'],
   "backend":["CMD-SHELL", """node -e "fetch('http://127.0.0.1:3001/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))" """ .strip()],
   "frontend":["CMD","node","-e","fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]}
  check(name in tests and h.get("test")==tests[name],"health command")
  check(h.get("timeout")=="5s" and h.get("interval")==("5s" if name=="frontend" else "10s") and h.get("retries")=={"mysql":10,"backend":5,"frontend":20}.get(name),"health timing")
  check(h.get("start_period")=={"mysql":"30s","backend":"10s"}.get(name),"health start period")
 for n in c.get("networks",{}).values():keys(n,["name","driver","internal","ipam"],"network")
 for v in c.get("volumes",{}).values():keys(v,["name","driver"],"volume")
 for v in c.get("secrets",{}).values():
  keys(v,["name","file"],"build secret");check(v.get("name")==p+"_proxy_ca","secret name")

def validate(c):
 strict(c)
 def check(ok,msg):
  if not ok: raise SystemExit("Development safety check: "+msg)
 check(host_port.isascii() and host_port.isdecimal() and str(int(host_port))==host_port and 1024<=int(host_port)<=65535,"frontend host port")
 check(set(c["services"])=={"mysql","backend","frontend"},"unexpected services")
 check(set(c["volumes"])=={"fullstack_mysql_data"},"unexpected volume")
 check(c["volumes"]["fullstack_mysql_data"]["name"]==p+"-mysql-data","volume name")
 check(set(c["networks"])=={"fullstack-network","dev-ingress"},"unexpected network")
 for key,suffix,internal in [("fullstack-network","network",True),("dev-ingress","ingress",False)]:
  n=c["networks"][key]
  check(n["name"]==p+"-"+suffix and n.get("internal",False)==internal and n.get("driver")=="bridge","network isolation")
  check(not any(n.get(k) for k in ["external","driver_opts","ipam","enable_ipv6","attachable"]),"unexpected network options")
 v=c["volumes"]["fullstack_mysql_data"]
 check(not any(v.get(k) for k in ["external","driver_opts"]) and v.get("driver","local")=="local","volume isolation")
 expected_env={"mysql":{"MYSQL_DATABASE":"fullstack","MYSQL_USER":"dev_app","MYSQL_PASSWORD":"dev_app_only","MYSQL_ROOT_PASSWORD":"dev_root_only"},"backend":{"PORT":"3001","DB_HOST":"mysql","DB_PORT":"3306","DB_NAME":"fullstack","DB_USER":"dev_app","DB_PASSWORD":"dev_app_only"},"frontend":{"HTTP_PROXY":"","HTTPS_PROXY":"","ALL_PROXY":"","NO_PROXY":"*"}}
 expected_mounts={"mysql":{("volume","fullstack_mysql_data","/var/lib/mysql",False),("bind",str(root/"mysql/init.sql"),"/opt/codex-dev/init.sql",True)},"backend":set(),"frontend":{("bind",str(root/"dev"/f),"/opt/codex-dev/"+f,True) for f in ["vite.config.mjs","test-stack.mjs"]}}
 for name,s in c["services"].items():
  check(s["container_name"]==p+"-"+name,"container name")
  image="mysql:9.7.2@sha256:79b171dd2361300260ebceb30bb1c669fa8f70183ae250773b56b62d9031338b" if name=="mysql" else p+"-"+name+":"+sha
  check(s["image"]==image,"image selection")
  check(s.get("environment",{})==expected_env[name],"environment values")
  check(s.get("restart")=="no" and s.get("platform")=="linux/amd64","runtime selection")
  check(set(s["networks"])==({"fullstack-network","dev-ingress"} if name=="frontend" else {"fullstack-network"}),"service network")
  check(all(not options for options in s["networks"].values()),"unexpected network attachment options")
  check(not any(s.get(k) for k in ["privileged","network_mode","pid","devices","cap_add","env_file","secrets","configs","volumes_from","extra_hosts"]),"unsafe runtime options")
  ports=s.get("ports",[]); check(len(ports)==(1 if name=="frontend" else 0),"port count")
  for port in ports:
   check(port["host_ip"]=="127.0.0.1" and str(port["published"])==host_port and port["target"]==3000 and port.get("protocol","tcp")=="tcp" and port.get("mode","ingress")=="ingress","port binding")
  mounts={(v["type"],v["source"],v["target"],v.get("read_only",False)) for v in s.get("volumes",[])}
  check(mounts==expected_mounts[name] and len(s.get("volumes",[]))==len(expected_mounts[name]),"mount allowlist")
  for mount in s.get("volumes",[]):
   check(not mount.get("bind",{}).get("propagation") and not mount.get("volume",{}).get("subpath"),"unexpected mount options")
  if name!="mysql":
   b=s["build"]; check(b["context"]==str(root/name) and b["dockerfile"]=="../dev/"+name+".Dockerfile","build source")
 for name,s in c["services"].items():
  check(not s.get("entrypoint"),"unexpected entrypoint")
  check(not s.get("pull_policy"),"unexpected pull policy")
  if name=="mysql":
   check(s.get("command")==["bash","-ec","cp /opt/codex-dev/init.sql /docker-entrypoint-initdb.d/01-init.sql; chmod 0444 /docker-entrypoint-initdb.d/01-init.sql; exec docker-entrypoint.sh mysqld"],"MySQL command")
  else:
   check(not s.get("command"),"unexpected application command")
   b=s["build"]
   check(not any(b.get(k) for k in ["args","additional_contexts","ssh","network","extra_hosts","privileged","entitlements"]),"unsafe build options")
   check(b.get("secrets")==[{"source":"proxy_ca"}],"build secrets")
 check(set(c["secrets"])=={"proxy_ca"} and c["secrets"]["proxy_ca"]["file"]==ca,"CA secret")

c=json.load(sys.stdin);validate(c)
if mode=="self-test":
 cases=[]
 def add(label,fn):
  value=copy.deepcopy(c);fn(value);cases.append((label,value))
 unsafe={"use_api_socket":True,"security_opt":["seccomp=unconfined"],"privileged":True,"cap_add":["SYS_ADMIN"],"cap_drop":["ALL"],"network_mode":"host","pid":"host","ipc":"host","uts":"host","userns_mode":"host","devices":["/dev/kvm"],"device_cgroup_rules":["a *:* rwm"],"gpus":"all","tmpfs":["/credentials"],"volumes_from":["other"],"sysctls":{"net.ipv4.ip_forward":"1"},"user":"0","group_add":["0"],"runtime":"nvidia","cgroup":"host","post_start":[{"command":"id"}],"credential_spec":{"file":"/credentials"},"develop":{"watch":[]},"x-unreviewed":True}
 for s in ("mysql","backend","frontend"):
  for k,v in unsafe.items():add(s+" "+k,lambda d,s=s,k=k,v=v:d["services"][s].update({k:v}))
 add("MySQL build",lambda d:d["services"]["mysql"].update(build={"labels":{"org.opencontainers.image.revision":sha}}))
 add("Docker socket",lambda d:d["services"]["frontend"]["volumes"].append({"type":"bind","source":"/var/run/docker.sock","target":"/var/run/docker.sock"}))
 for s in ("mysql","backend"):
  add(s+" publication",lambda d,s=s:d["services"][s].update(ports=copy.deepcopy(d["services"]["frontend"]["ports"])))
  add(s+" ingress",lambda d,s=s:d["services"][s]["networks"].update({"dev-ingress":None}))
 for h in ("0.0.0.0","::","::1"):add("host "+h,lambda d,h=h:d["services"]["frontend"]["ports"][0].update(host_ip=h))
 add("wrong host port",lambda d:d["services"]["frontend"]["ports"][0].update(published=str(int(host_port)+1)))
 add("wrong container port",lambda d:d["services"]["frontend"]["ports"][0].update(target=3100))
 add("UDP",lambda d:d["services"]["frontend"]["ports"][0].update(protocol="udp"))
 add("production name",lambda d:d["services"]["backend"].update(container_name="fullstack-backend"))
 add("production image",lambda d:d["services"]["backend"].update(image="ghcr.io/derbswag/fullstack-backend:latest"))
 add("unexpected credentials",lambda d:d["services"]["backend"]["environment"].update(DB_PASSWORD="unexpected"))
 add("extra network",lambda d:d["networks"].update(extra={"driver":"bridge"}))
 add("external volume",lambda d:d["volumes"]["fullstack_mysql_data"].update(external=True))
 add("volume host options",lambda d:d["volumes"]["fullstack_mysql_data"].update(driver_opts={"device":"/prod","o":"bind","type":"none"}))
 add("unsafe build",lambda d:d["services"]["backend"]["build"].update(ssh=["default"]))
 add("health command",lambda d:d["services"]["backend"]["healthcheck"].update(test=["CMD","sh","-c","id"]))
 for label,value in cases:
  try:validate(value)
  except (SystemExit,KeyError,TypeError,ValueError):continue
  raise SystemExit("UNSAFE VARIANT ACCEPTED: "+label)
 print("PASS: approved model and "+str(len(cases))+" negative security variants")
else:print("Development resource safety checks passed",file=sys.stderr)
PYVALIDATE
)
printf '%s' "$rendered" | python3 -c "$validation_code" "$root" "$project" "$sha" "$ca" "$frontend_port" "${1:-}"

# Refuse pre-existing names belonging to another project before any action.
for service in mysql backend frontend; do
 owner=$(docker_local container ls -a --filter "name=^/${project}-${service}$" --format '{{.Names}} {{.Label "com.docker.compose.project"}}')
 [[ -z $owner || $owner == "$project-$service $project" ]] || fail 'container ownership mismatch'
done
for resource in volume:mysql-data network:network network:ingress; do
 kind=${resource%%:*}
 suffix=${resource#*:}
 name="$project-$suffix"
 existing=$(docker_local "$kind" ls --filter "name=^${name}$" --format '{{.Name}}')
 if [[ -n $existing ]]; then
   owner=$(docker_local "$kind" inspect "$name" --format '{{index .Labels "com.docker.compose.project"}}')
   [[ $owner == "$project" ]] || fail "$kind ownership mismatch"
   docker_local "$kind" inspect "$name" | python3 -c '
import json,sys
kind,name,project=sys.argv[1:];r=json.load(sys.stdin)[0]
if kind=="volume":
 if r["Driver"]!="local" or r.get("Options"): raise SystemExit("Development safety check: unsafe live volume")
else:
 if r["Driver"]!="bridge" or r["Internal"]!=(name==project+"-network") or r.get("Options"): raise SystemExit("Development safety check: unsafe live network")
 if not all(v["Name"] in {project+"-"+s for s in ["mysql","backend","frontend"]} for v in r.get("Containers",{}).values()): raise SystemExit("Development safety check: foreign network member")
' "$kind" "$name" "$project"
 fi
done
# A running frontend from this exact project may retain its own selected port.
# Otherwise require a free IPv4 loopback bind before any container creation.
check_frontend_port() {
 local state='[]'
 if [[ -n $(docker_local container ls -a --filter "name=^/${project}-frontend$" --format '{{.Names}}') ]]; then
   state=$(docker_local container inspect "$project-frontend")
 fi
 printf '%s' "$state" | python3 -c '
import json,socket,sys
port=int(sys.argv[1]); project=sys.argv[2]; containers=json.load(sys.stdin)
owned=False
for c in containers:
 expected=[{"HostIp":"127.0.0.1","HostPort":str(port)}]
 owned=(c["Name"]=="/"+project+"-frontend" and c["Config"].get("Labels",{}).get("com.docker.compose.project")==project and c["State"]["Running"] and c["NetworkSettings"].get("Ports",{}).get("3000/tcp")==expected)
try:
 with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as s:
  s.bind(("127.0.0.1",port))
except OSError as e:
 if not owned: raise SystemExit("Development safety check: frontend host port collision on 127.0.0.1:"+str(port)+": "+str(e))
print("Frontend host port preflight passed: 127.0.0.1:"+str(port),file=sys.stderr)
' "$frontend_port" "$project"
}

check_source_copies() {
 python3 - "$root" <<'PYSOURCES'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
for name in ["backend","frontend"]:
 p=r/name
 if not p.is_dir() or p.is_symlink(): raise SystemExit("Development safety check: source context symlink: "+name)
def tree(folder,extensions):
 p=r/folder
 if not p.is_dir() or p.is_symlink(): raise SystemExit("Development safety check: unsafe source directory: "+folder)
 for f in p.rglob("*"):
  if f.is_symlink(): raise SystemExit("Development safety check: source symlink: "+str(f))
  if f.is_file():
   n=f.name.lower()
   if f.suffix.lower() not in extensions or n.startswith((".env",".npmrc",".netrc")) or any(x in n for x in ["credential","secret","private-key","id_rsa","id_ed25519"]): raise SystemExit("Development safety check: unreviewed source file: "+str(f))
for name in ["backend/package.json","backend/package-lock.json","backend/index.js","frontend/package.json","frontend/package-lock.json","frontend/index.html","frontend/vite.config.js","frontend/.oxlintrc.json"]:
 f=r/name
 if not f.is_file() or f.is_symlink(): raise SystemExit("Development safety check: unreviewed copy source: "+name)
tree("backend/src",{".js"});tree("frontend/src",{".js",".jsx",".css",".svg",".png"});tree("frontend/public",{".svg",".png",".ico"})
print("Explicit build-copy preflight passed",file=sys.stderr)
PYSOURCES
}
up_stack() {
 check_frontend_port
 local new_volume=false
 [[ -n $(docker_local volume ls --filter "name=^${project}-mysql-data$" --format '{{.Name}}') ]] || new_volume=true
 if ! compose up -d --wait --wait-timeout 240 --no-build --pull never mysql backend frontend; then
   compose ps --all || true
   compose logs --tail 100 || true
   return 1
 fi
 if [[ $new_volume == true ]]; then
   compose exec -T frontend node /opt/codex-dev/test-stack.mjs --seeds-only --fresh
 fi
}
host_http() {
 python3 - "$frontend_port" <<'PYHTTP'
import http.client,json,sys
port=int(sys.argv[1]);c=http.client.HTTPConnection("127.0.0.1",port,timeout=5)
c.request("GET","/");r=c.getresponse()
if r.status!=200 or b'id="root"' not in r.read(): raise SystemExit("Development safety check: React HTTP response invalid")
c.request("GET","/api/health");r=c.getresponse()
if r.status!=200 or json.load(r)["database"]!="connected": raise SystemExit("Development safety check: backend HTTP/database response invalid")
c.close();print(f"PASS: React http://127.0.0.1:{port}; API http://127.0.0.1:{port}/api/health")
PYHTTP
}
optimization_regressions() {
 python3 - "$root" "$project" "$sha" "$ca" "$frontend_port" "$rendered" <<'PYOPTTEST'
import copy,json,os,pathlib,re,subprocess,sys
root,project,sha,ca,port,rendered=sys.argv[1:]
text=(pathlib.Path(root)/"dev/compose.sh").read_text()
def block(start,end):
 return text.split(start,1)[1].split(end,1)[0]
version_code=block('python3 - "$version" <<'+"'PY'\n","\nPY")
model_code=block("<<'PYVALIDATE'\n","\nPYVALIDATE")
live_code=block('docker_local "$kind" inspect "$name" | python3 -c '+"'\n","\n' \"$kind\"")
source_code=block("<<'PYSOURCES'\n","\nPYSOURCES")
http_code=block("<<'PYHTTP'\n","\nPYHTTP")
def require(ok,message):
 if not ok: raise SystemExit("Optimization regression failed: "+message)
# Virtual filesystems and HTTP clients avoid filesystem or service changes.
# Each child executes the real enforcement block extracted from this file.
source_fixture=r'''
import pathlib,sys
case=sys.argv[1];Pure=pathlib.PurePosixPath
class ReviewPath:
 def __init__(self,value):self.value=str(value)
 def __truediv__(self,value):return ReviewPath(self.value+"/"+value)
 def __str__(self):return self.value
 def is_dir(self):
  return not ((case=="missing-context" and self.value=="/review/backend") or (case=="missing-tree" and self.value=="/review/backend/src"))
 def is_symlink(self):
  targets={"context-link":"/review/backend","tree-link":"/review/backend/src","file-link":"/review/backend/src/helper.js","copy-link":"/review/backend/index.js"}
  return self.value==targets.get(case)
 def is_file(self):return not (case=="missing-copy" and self.value=="/review/backend/index.js")
 def rglob(self,pattern):
  names={"dotenv":".env.local","npmrc":".npmrc","netrc":".netrc","private-key":"private.pem","secret":"secret.js","extension":"notes.txt"}
  return [ReviewPath(self.value+"/"+names.get(case,"helper.js"))] if self.value=="/review/backend/src" else []
 @property
 def name(self):return Pure(self.value).name
 @property
 def suffix(self):return Pure(self.value).suffix
pathlib.Path=ReviewPath
sys.argv=["source-check","/review"]
'''
http_fixture=r'''
import http.client,io,json,sys
case=sys.argv[1]
class Response(io.BytesIO):
 def __init__(self,status,body):super().__init__(body);self.status=status
class ReviewHTTP:
 def __init__(self,host,port,timeout):
  if host!="127.0.0.1" or port!=3200:raise SystemExit("unexpected HTTP destination")
 def request(self,method,path):
  if method!="GET" or path not in ["/","/api/health"]:raise SystemExit("unexpected HTTP request")
  self.path=path
 def getresponse(self):
  if self.path=="/":
   return Response(503 if case=="root-status" else 200,b"missing" if case=="root-html" else b'<div id="root"></div>')
  return Response(503 if case=="health-status" else 200,json.dumps({"database":"disconnected" if case=="health-body" else "connected"}).encode())
 def close(self):pass
http.client.HTTPConnection=ReviewHTTP
sys.argv=["http-check","3200"]
'''
for mode in [None,"1","2"]:
 env=os.environ.copy()
 if mode is None:env.pop("PYTHONOPTIMIZE",None)
 else:env["PYTHONOPTIMIZE"]=mode
 env["PYTHONDONTWRITEBYTECODE"]="1"
 def run(label,code,args=(),data=None,valid=True):
  result=subprocess.run([sys.executable,"-c",code,*args],input=data,text=True,capture_output=True,env=env)
  require(result.returncode==(0 if valid else 1),label+" wrong exit: "+str(result.returncode)+" "+result.stderr)
  if not valid:require("Development safety check:" in result.stderr,label+" failed for an unexpected reason: "+result.stderr)
  return result
 flag=run("optimization flag","import sys;print(sys.flags.optimize)")
 require(flag.stdout.strip()==("0" if mode is None else mode),"requested optimization mode not active")
 model=run("Compose model and negative variants",model_code,[root,project,sha,ca,port,"self-test"],rendered)
 match=re.search(r"and (\d+) negative security variants",model.stdout)
 require(match is not None,"Compose negative variants did not run")
 source_cases=["clean","dotenv","npmrc","netrc","private-key","secret","extension","context-link","tree-link","file-link","copy-link","missing-context","missing-tree","missing-copy"]
 for case in source_cases:
  run("source "+case,source_fixture+"\nexec("+repr(source_code)+")",[case],valid=case=="clean")
 for value,valid in [("2.24.3",False),("invalid",False),("2.24.4",True),("v2.40.3",True)]:
  run("Compose version "+value,version_code,[value],valid=valid)
 volume={"Driver":"local","Options":None}
 network={"Driver":"bridge","Internal":True,"Options":{},"Containers":{"one":{"Name":project+"-mysql"}}}
 ingress={"Driver":"bridge","Internal":False,"Options":{},"Containers":{"one":{"Name":project+"-frontend"}}}
 live=[("approved-volume","volume",project+"-mysql-data",volume,True),
       ("approved-network","network",project+"-network",network,True),
       ("approved-ingress","network",project+"-ingress",ingress,True)]
 def changed(value,**fields):
  result=copy.deepcopy(value);result.update(fields);return result
 live.extend([
  ("host-bind-volume","volume",project+"-mysql-data",changed(volume,Options={"type":"none","o":"bind","device":"/unexpected"}),False),
  ("volume-driver","volume",project+"-mysql-data",changed(volume,Driver="nfs"),False),
  ("application-isolation","network",project+"-network",changed(network,Internal=False),False),
  ("ingress-isolation","network",project+"-ingress",changed(ingress,Internal=True),False),
  ("network-driver","network",project+"-network",changed(network,Driver="host"),False),
  ("network-options","network",project+"-network",changed(network,Options={"unexpected":"true"}),False),
  ("foreign-member","network",project+"-network",changed(network,Containers={"other":{"Name":"unrelated-project"}}),False)])
 for label,kind,name,value,valid in live:
  run(label,live_code,[kind,name,project],json.dumps([value]),valid)
 for case in ["clean","root-status","root-html","health-status","health-body"]:
  run("HTTP "+case,http_fixture+"\nexec("+repr(http_code)+")",[case],valid=case=="clean")
 negatives=int(match.group(1))+len(source_cases)-1+2+sum(not item[-1] for item in live)+4
 print("PASS: PYTHONOPTIMIZE="+("unset" if mode is None else mode)+": "+str(negatives)+" negative checks ("+match.group(1)+" Compose, 13 source, 7 live resources, 2 version, 4 HTTP); approved controls passed")
PYOPTTEST
}
case "${1:-}" in
 config) [[ $# == 1 || ( $# == 2 && $2 == --quiet ) ]] || fail 'config arguments'; compose "$@";;
 self-test) [[ $# == 1 ]] || fail 'self-test arguments'; optimization_regressions;;
 check-port) [[ $# == 1 ]] || fail 'check-port arguments'; check_frontend_port;;
 pull) [[ $# == 2 && $2 == mysql ]] || fail 'pull arguments'; compose "$@";;
 build)
   [[ $# == 3 && $2 == backend && $3 == frontend ]] || fail 'build arguments'
   check_source_copies
   buildx_config=$(mktemp -d /tmp/fullstack-codex-buildx.XXXXXX)
   compose "$@";;
 start) [[ $# == 1 ]] || fail 'start arguments'; up_stack; host_http;;
 up) [[ "$*" == 'up -d --wait --wait-timeout 240 --no-build --pull never mysql backend frontend' ]] || fail 'up arguments'; up_stack;;
 test)
   [[ $# == 1 ]] || fail 'test arguments'
   host_http
   compose exec -T frontend node /opt/codex-dev/test-stack.mjs
   compose exec -T frontend node /opt/codex-dev/test-stack.mjs --self-test
   compose exec -T frontend npm run lint
   compose exec -T frontend npm run build;;
 exec)
   [[ "$*" == 'exec -T frontend node /opt/codex-dev/test-stack.mjs' || "$*" == 'exec -T frontend npm run lint' || "$*" == 'exec -T frontend npm run build' ]] || fail 'exec arguments'
   compose "$@";;
 ps) [[ "$*" == ps || "$*" == 'ps --all' ]] || fail 'ps arguments'; compose "$@";;
 logs) [[ "$*" == 'logs --tail 100' ]] || fail 'logs arguments'; compose "$@";;
 stop) [[ $# == 1 ]] || fail 'stop arguments'; compose stop;;
 *) fail 'unsupported command';;
esac
