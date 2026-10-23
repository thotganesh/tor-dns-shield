import subprocess, yaml, re, sys, itertools, tempfile, os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..'))
def run(args):
    return subprocess.run(['./install.sh','--dry-run','--non-interactive']+args,capture_output=True,text=True)
def compose(out):
    m=re.search(r'######## [^\n]*docker-compose.yml ########\n(.*?)(?:\n==> dry-run)',out,re.S)
    return yaml.safe_load(m.group(1))
fails=0
def check(name,cond):
    global fails
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: fails+=1
ob=tempfile.NamedTemporaryFile('w',delete=False,suffix='.conf'); ob.write('Bridge obfs4 203.0.113.5:443 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA cert=xyz iat-mode=0\n'); ob.close()
n=0
for res,tr,ag,sp,cc in itertools.product(['quad9','adguard','cloudflare'],['snowflake','direct','obfs4'],['--adguard','--no-adguard'],['--snowflake-proxy','--no-snowflake-proxy'],['fr,it','none','de']):
    args=['--resolver',res,'--transport',tr,ag,sp,'--countries',cc]
    if tr=='obfs4': args+=['--obfs4-bridges-file',ob.name]
    r=run(args); n+=1
    ok=r.returncode==0
    if ok:
        c=compose(r.stdout); s=c['services']
        ok &= ('adguard' in s)==(ag=='--adguard')
        ok &= ('snowflake-proxy' in s)==(sp=='--snowflake-proxy')
        # exactly one service publishes port 53, only on 127.0.0.1
        pub=[k for k,v in s.items() if any(':53:' in p for p in v.get('ports',[]))]
        ok &= len(pub)==1 and all(p.startswith('127.0.0.1:') for p in s[pub[0]]['ports'])
        ok &= 'ports' not in s['tor']
        t=r.stdout
        ok &= ('ExcludeExitNodes' in t)==(cc!='none')
        ok &= ('snowflake-client' in t)==(tr=='snowflake') and ('lyrebird' in t)==(tr=='obfs4')
        ok &= ('UseBridges 1' in t)==(tr!='direct')
    if not ok: print('FAIL combo',args); fails+=1
print('combos run:',n)
# error cases
check('bad country rejected', run(['--countries','fra']).returncode!=0)
check('bad country digits rejected', run(['--countries','f1']).returncode!=0)
check('bad resolver rejected', run(['--resolver','evil']).returncode!=0)
check('obfs4 without file rejected', run(['--transport','obfs4']).returncode!=0)
check('custom without names rejected', run(['--resolver','custom']).returncode!=0)
r=run(['--resolver','custom','--server-names','a-b,c.d']); check('custom names ok', r.returncode==0 and "'a-b', 'c.d'" in r.stdout)
check('custom injection rejected', run(['--resolver','custom','--server-names',"x'];evil"]).returncode!=0)
check('capacity non-numeric rejected', run(['--capacity','x;rm']).returncode!=0)
r=run(['--listen-ip','0.0.0.0','--no-adguard']); check('0.0.0.0 warns', r.returncode==0 and 'open resolver' in r.stderr)
check('unknown option rejected', run(['--bogus']).returncode!=0)
r=run([]); check('non-interactive defaults: snowflake proxy ON', 'snowflake-proxy:' in r.stdout)
env=dict(os.environ,TDS_COUNTRIES='fr',TDS_SNOWFLAKE_PROXY='no')
r=subprocess.run(['./install.sh','--dry-run','--non-interactive'],capture_output=True,text=True,env=env)
check('env vars honoured', 'ExcludeExitNodes {fr}' in r.stdout and 'snowflake-proxy:' not in r.stdout)
print('FAILS:',fails); sys.exit(1 if fails else 0)
