#!/usr/bin/env python3
"""Tiny stand-in for Supabase (REST + Auth OTP + the credit RPCs) for local testing only.
Any email works; the 6-digit code is always 123456. Codes are 'issued' 4 seconds after redeem."""
import json,http.server,datetime,time,threading,random,string,urllib.parse as u
ROWS=[];USERS={};MEMBERS={};LEDGER=[];REDEMPTIONS=[];TOK={}
WEEKLY={'game':'knockout','target':6000}
def now():return datetime.datetime.utcnow().isoformat()
def week(uid):return sum(l['cents'] for l in LEDGER if l['uid']==uid and l['cents']>0)
def bal(uid):return max(0,sum(l['cents'] for l in LEDGER if l['uid']==uid))
def give(uid,key,c):
  if any(l['uid']==uid and l['key']==key for l in LEDGER):return 0
  c=min(c,max(1000-week(uid),0))
  if c<=0:return 0
  LEDGER.append({'uid':uid,'key':key,'cents':c});return c
def wallet(uid):
  m=MEMBERS.get(uid)
  if not m:return {'member':False}
  done=any(l['uid']==uid and l['key'].startswith('week:') for l in LEDGER)
  r=[x for x in REDEMPTIONS if x['uid']==uid];lc=r[-1] if r else None
  return {'member':True,'email':m['email'],'initials':m['initials'],'ref_code':m['ref'],'balance':bal(uid),'week':week(uid),'cap':1000,
    'referrals':sum(1 for x in MEMBERS.values() if x.get('by')==uid),'weekly':dict(WEEKLY,done=done),
    'last_code':None if not lc else {'id':lc['id'],'status':lc['status'],'code':lc.get('code'),'dollars':lc['dollars'],'at':lc['at']}}
class H(http.server.BaseHTTPRequestHandler):
  def _h(self,code=200,extra=None):
    self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Access-Control-Allow-Origin','*');self.send_header('Access-Control-Allow-Headers','*');self.send_header('Access-Control-Expose-Headers','content-range')
    for k,v in (extra or {}).items():self.send_header(k,v)
    self.end_headers()
  def _j(self,o,code=200):self._h(code);self.wfile.write(json.dumps(o).encode())
  def do_OPTIONS(self):self._h(204)
  def uid(self):
    t=(self.headers.get('Authorization') or '').replace('Bearer ','');return TOK.get(t)
  def do_POST(self):
    n=int(self.headers.get('Content-Length',0));d=json.loads(self.rfile.read(n) or b'{}');p=u.urlparse(self.path).path
    if p=='/auth/v1/otp':USERS.setdefault(d['email'],'u'+str(len(USERS)+1));self._j({});return
    if p=='/auth/v1/verify':
      if d.get('token')!='123456':self._j({'msg':'Token has expired or is invalid'},403);return
      uid=USERS.setdefault(d['email'],'u'+str(len(USERS)+1));t='tok_'+uid+'_'+str(random.random());TOK[t]=uid
      self._j({'access_token':t,'refresh_token':'r'+t,'expires_in':3600,'user':{'email':d['email']}});return
    if p=='/auth/v1/logout':self._h(204);return
    if p.startswith('/rest/v1/rpc/'):
      uid=self.uid()
      if not uid:self._j({'message':'permission denied'},401);return
      fn=p.split('/')[-1]
      if fn=='arcade_wallet':self._j(wallet(uid));return
      if fn=='arcade_register':
        new=uid not in MEMBERS
        if new:
          email=[e for e,x in USERS.items() if x==uid][0];ref=''.join(random.choices(string.ascii_uppercase+string.digits,k=6))
          by=None
          if d.get('p_ref'):
            by=next((k for k,m in MEMBERS.items() if m['ref']==d['p_ref'].upper() and k!=uid),None)
          MEMBERS[uid]={'email':email,'initials':d.get('p_initials'),'ref':ref,'by':by};give(uid,'welcome',500)
          if by:give(by,'ref:'+uid,500)
        elif d.get('p_initials'):MEMBERS[uid]['initials']=d['p_initials']
        self._j({'new':new,'wallet':wallet(uid)});return
      if fn=='arcade_weekly_claim':
        g=0
        if d.get('p_game')==WEEKLY['game'] and int(d.get('p_score',0))>=WEEKLY['target']:g=give(uid,'week:2026-10-05',200)
        self._j({'given':g,'wallet':wallet(uid)});return
      if fn=='arcade_redeem':
        if any(x['uid']==uid and x['status']=='pending' for x in REDEMPTIONS):self._j({'ok':False,'reason':'pending'});return
        b=bal(uid);dl=min(50,b//100)
        if dl<5:self._j({'ok':False,'reason':'balance','balance':b,'need':500});return
        r={'id':'rd'+str(len(REDEMPTIONS)+1),'uid':uid,'dollars':dl,'status':'pending','at':now()};REDEMPTIONS.append(r);LEDGER.append({'uid':uid,'key':'redeem:'+r['id'],'cents':-dl*100})
        def issue():
          time.sleep(4);r['status']='issued';r['code']='KA'+''.join(random.choices(string.ascii_uppercase+string.digits,k=6))+str(dl)
        threading.Thread(target=issue,daemon=True).start()
        self._j({'ok':True,'id':r['id'],'dollars':dl,'wallet':wallet(uid)});return
      self._j({'message':'unknown rpc'},404);return
    d['created_at']=now();ROWS.append(d);self._h(201);self.wfile.write(b'')
  def do_GET(self):
    p=u.urlparse(self.path).path;q=u.parse_qs(u.urlparse(self.path).query)
    if p.endswith('arcade_weekly'):self._j([WEEKLY]);return
    if 'arcade_scores' in p:self._h(200,{'content-range':'0-0/%d'%len(ROWS)});self.wfile.write(b'[]');return
    rows=ROWS[:]
    if 'game' in q:rows=[r for r in rows if r['game']==q['game'][0].replace('eq.','')]
    if 'month' in q:rows=[r for r in rows if r['month']==q['month'][0].replace('eq.','')]
    best={}
    for r in rows:
      k=(r['game'],r['initials'])
      if k not in best or r['score']>best[k]['score']:best[k]=r
    out=sorted(best.values(),key=lambda r:-r['score'])[:10];self._j(out)
  def log_message(self,*a):pass
http.server.ThreadingHTTPServer(('127.0.0.1',8799),H).serve_forever()
