from pathlib import Path
from decimal import Decimal
from collections import defaultdict
from xml.sax.saxutils import escape
import json
import sys
import os
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph

HERE = Path(__file__).resolve().parent
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1]
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / 'apresentacao-parte-2-g09.pdf'
EVIDENCE = ROOT / 'evidencias/av2/brutas'
FONTS = Path(os.environ.get('AV2_FONT_DIR', '/System/Library/Fonts/Supplemental'))
for name, file in [('Arial', 'Arial.ttf'), ('ArialBold', 'Arial Bold.ttf'), ('ArialItalic', 'Arial Italic.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(FONTS / file)))
pdfmetrics.registerFontFamily('Arial', normal='Arial', bold='ArialBold', italic='ArialItalic', boldItalic='ArialBold')

W, H = 1280, 720
INK, MUTED, PAPER = '#142F39', '#51636A', '#FAF8F3'
ORANGE, TEAL, RULE = '#B44C20', '#167D78', '#CDD5D5'
WHITE, PALE = '#FFFFFF', '#E7EEEB'
COLORS = {'delivered': '#174E60', 'paid': '#29847F', 'shipped': '#7CB8B1', 'pending': '#D9DBD3', 'cancelled': '#C96C36'}
STATUSES = ['delivered', 'paid', 'shipped', 'pending', 'cancelled']
FINAL = EVIDENCE / 'fechamento-21-11-2026'
validation = json.loads((FINAL / 'validacao-final.json').read_text())
assert validation['pipeline_passed'] and validation['backfill_passed']
raw = json.loads((FINAL / 'athena-results.json').read_text())['ResultSet']['Rows']
keys = [v['VarCharValue'] for v in raw[0]['Data']]
rows = [dict(zip(keys, [v['VarCharValue'] for v in r['Data']])) for r in raw[1:]]
totals, daily = defaultdict(Decimal), defaultdict(dict)
for r in rows:
    totals[r['status']] += Decimal(r['gross_sales'])
    daily[r['order_date']][r['status']] = Decimal(r['gross_sales'])
TOTAL = sum(totals.values())
assert len(rows) == 150 and TOTAL == Decimal('526021301.72')
assert sum(int(r['item_count']) for r in rows) == 174878
OUT.parent.mkdir(parents=True, exist_ok=True)
c = canvas.Canvas(str(OUT), pagesize=(W, H), pageCompression=1, initialFontName='Arial')
c.setTitle('Data Lake de pedidos | AV2 | Grupo 09')
c.setAuthor('Renato Santana, João Augusto Pimentel, Raphael Barros e Lara Pessoa')
c.setSubject('Engenharia de Dados, CESAR School, 2026.2. Apresentação e apoio técnico.')
layouts = []
page = 0

def color(v):
    return HexColor(v)

def rect(x, y, w, h, fill, stroke=None):
    c.setFillColor(color(fill))
    c.setStrokeColor(color(stroke or fill))
    c.rect(x, H-y-h, w, h, fill=1, stroke=bool(stroke))

def line(x, y, x2, y2=None, col=RULE, width=1):
    c.setStrokeColor(color(col))
    c.setLineWidth(width)
    c.line(x, H-y, x2, H-(y if y2 is None else y2))

def text(s, x, y, size=22, col=INK, bold=False, maxw=None):
    font = 'ArialBold' if bold else 'Arial'
    sw = pdfmetrics.stringWidth(s, font, size)
    if maxw is not None:
        assert sw <= maxw + .1, (page, s, sw, maxw)
    c.setFillColor(color(col))
    c.setFont(font, size)
    c.drawString(x, H-y-size*.82, s)
    layouts.append([page, s, x, y, sw, size])

def para(s, x, y, w, size=22, col=INK, bold=False, maxh=200, leading=None):
    style = ParagraphStyle('p', fontName='ArialBold' if bold else 'Arial', fontSize=size,
                           leading=leading or size*1.3, textColor=color(col), spaceAfter=0)
    p = Paragraph(s, style)
    pw, ph = p.wrap(w, H)
    assert ph <= maxh + .1, (page, s[:100], ph, maxh)
    assert y + ph < 660, (page, s[:80], y+ph)
    p.drawOn(c, x, H-y-ph)
    layouts.append([page, s, x, y, w, ph])
    return ph

def start(title, subtitle, section, dark=False):
    global page
    if page:
        c.showPage()
    page += 1
    c.bookmarkPage(f'p{page}')
    c.addOutlineEntry(title, f'p{page}', 0)
    bg = INK if dark else PAPER
    rect(0, 0, W, H, bg)
    text(section.upper(), 64, 39, 14, '#E8A77A' if dark else ORANGE, True)
    text(title, 64, 79, 38, WHITE if dark else INK, True, 1152)
    if subtitle:
        para(subtitle, 64, 137, 1140, 20, '#D6E1E1' if dark else MUTED, maxh=58)
    line(64, 671, 1216, col='#45616A' if dark else RULE)
    text('CESAR School   /   Engenharia de Dados 2026.2   /   Grupo 09', 64, 687, 12, '#CAD7D8' if dark else MUTED)
    text(f'{page:02d}' + ('  /  APOIO' if page > 8 else ''), 1120, 687, 12, '#CAD7D8' if dark else MUTED, maxw=96)

def source(s):
    text('Fontes: ' + s, 64, 646, 12, MUTED, maxw=1152)

def heading(s, x, y, w=520):
    text(s, x, y, 25, INK, True, w)

def table(headers, data, widths, x=64, y=214, size=20, rowh=65):
    totalw = sum(widths)
    rect(x, y, totalw, 42, INK)
    cur = x
    for hd, width in zip(headers, widths):
        text(hd, cur+14, y+12, 16, WHITE, True, width-28)
        cur += width
    y += 42
    for idx, row in enumerate(data):
        if idx % 2 == 0:
            rect(x, y, totalw, rowh, '#EEF1ED')
        cur = x
        for j, (s, width) in enumerate(zip(row, widths)):
            para(s, cur+14, y+12, width-28, size, bold=j==0, maxh=rowh-18, leading=size*1.23)
            cur += width
        line(x, y+rowh, x+totalw)
        y += rowh
    return y

def fmt(n, digits=2):
    return f'{n:,.{digits}f}'.replace(',', 'X').replace('.', ',').replace('X', '.')

start('Data Lake de pedidos', '', 'AV2  /  Pedidos de e-commerce', True)
text('Qual foi o valor bruto de vendas', 64, 172, 38, WHITE, True, 1100)
text('por dia e por status dos pedidos?', 64, 222, 38, WHITE, True, 1100)
para('Um pipeline reproduzível na AWS, da chegada do evento<br/>à consulta de negócio com qualidade e controle de acesso.',
     64, 303, 1000, 24, '#D6E1E1', maxh=75)
for x, val, lab in [(64,'187.854','eventos na raw'),(440,'174.878','itens únicos na trusted'),(842,'150','grupos na refined')]:
    line(x, 424, x+325, col='#527079')
    text(val, x, 450, 49, '#F2AD75', True)
    text(lab, x, 510, 20, '#DFE9E8')
para('Renato Santana (representante), João Augusto Pimentel,<br/>Raphael Barros e Lara Pessoa',64,575,1000,18,WHITE,maxh=55)
text('Dataset sintético de setembro de 2026. Valor bruto inclui cancelados e não representa receita reconhecida.',64,646,12,'#D6E1E1',maxw=1152)

start('Arquitetura e contrato dos dados', 'A data de chegada preserva o evento. A data do pedido organiza a análise e o reprocessamento.', '01  /  Do evento à consulta')
table(['CAMADA','RAW','TRUSTED','REFINED'],[
    ['Grão','Evento recebido<br/>com reentregas','Item vigente<br/>(pedido, item)','Dia do pedido<br/>e status'],
    ['Formato e volume','NDJSON<br/>46,54 MB','Parquet<br/>5,58 MB','Parquet<br/>50,86 KB'],
    ['Partição','arrival_date<br/>33 dias de chegada','order_date<br/>30 dias de evento','order_date<br/>30 dias de evento'],
], [150,334,334,334], y=204, size=21, rowh=75)
rect(64,483,1152,38,PALE)
rect(64,483,6,38,TEAL)
iac='Infraestrutura: '
iacw=pdfmetrics.stringWidth(iac,'ArialBold',20)
text(iac,88,493,20,TEAL,True)
text('Terraform modular; estado remoto em S3 com lock no DynamoDB; workspace av2.',88+iacw,493,20,INK,maxw=1104-iacw)
heading('Glue transforma',64,535,350)
para('Normaliza, valida, deduplica e agrega.<br/>Glue 4.0, Spark, 2 workers G.1X.',64,571,350,20,maxh=80)
heading('Catálogo descreve',464,535,350)
para('Schema no Terraform e partition<br/>projection, sem crawler.',464,571,350,20,maxh=80)
heading('Athena responde',864,535,350)
para('SQL sobre a refined, filtrada por data.<br/>Workgroup com teto de 10 MiB.',864,571,350,20,maxh=80)
source('DECISOES.md §§1, 4 e 5; módulos Terraform; inventory-recreated-final.json. MB e KB decimais.')

start('Qualidade antes da agregação', '120 mil pedidos base em 30 dias. A seed 20261118 reproduz os dados e a sujeira plantada.', '02  /  Transformação')
text('187.854 eventos recebidos',64,202,24,INK,True)
segments = [(174878, TEAL),(1802, ORANGE),(11174, '#B9C7C8')]
x=64
for count,col in segments:
    bw=1152*count/187854
    rect(x,251,bw,46,col)
    x+=bw
text('0',64,308,14,MUTED)
text('187.854',1147,308,14,MUTED)
for x,val,label,col in [(64,'174.878','itens únicos (93,1%)',TEAL),(464,'1.802','duplicatas removidas (1,0%)',ORANGE),(864,'11.174','rejeitados (5,9%)',MUTED)]:
    text(val,x,351,38,col,True)
    text(label,x,398,19,MUTED)
heading('Normalização',64,462,350)
para('Espaços e caixa de status/UF.<br/>Preço com vírgula para decimal.<br/>Datas e números tipados.',64,502,350,21,maxh=100)
heading('Validação',464,462,350)
para('Chaves e cliente preenchidos.<br/>5 status e 27 UFs aceitos.<br/>Data válida, preço e quantidade &gt; 0.',464,502,350,21,maxh=100)
heading('Deduplicação',864,462,350)
para('Chave: pedido + item.<br/>Maior updated_at, depois<br/>arrival_date e SHA-256 do<br/>conteúdo normalizado.',864,502,350,20,maxh=110)
source('generation-summary.json; pipeline-full-20261119T030340Z-report.json; pipeline_orders.py. Barra em escala linear.')

start('Reexecução estável e backfill isolado', 'Os testes comparam resultados e objetos. Cada evidência responde a uma hipótese específica.', '03  /  Confiabilidade')
heading('Duas execuções FULL',64,204,550)
table(['MÉTRICA','ANTES','DEPOIS'],[
    ['Linhas / chaves','174.878','174.878'],['Partições','30','30'],['Valor bruto','R$ 526,02 mi','R$ 526,02 mi']
], [220,170,170], x=64,y=251,size=20,rowh=58)
para('<b>Prova reforçada:</b> métricas e SHA-256<br/>do conteúdo de trusted, refined e quarentena.<br/>FULL completo; BACKFILL por order_date.',64,501,550,21,maxh=100)
heading('Backfill de 15/09/2026',684,204,530)
text('5.881',684,265,40,INK,True)
text('eventos válidos selecionados',852,275,19,MUTED)
line(684,327,1216)
text('- 60',684,350,34,ORANGE,True)
text('duplicatas válidas removidas',852,359,19,MUTED)
line(684,408,1216)
text('5.821',684,431,40,TEAL,True)
text('itens gravados em uma partição',852,442,19,MUTED)
para('<b>29 outras partições intactas por camada.</b><br/>Chave, ETag, tamanho e LastModified iguais.<br/>Prova reprocessamento seletivo, não nova chegada após o FULL.',684,510,530,20,maxh=105)
source('fechamento-21-11-2026: idempotency.json; backfill-report.json; backfill-isolation.json. Código final identificado por SHA-256.')

start('Valor bruto por dia e status', 'Setembro de 2026. A regularidade dos valores vem do gerador sintético, sem inferência comercial.', '04  /  Resposta à pergunta')
chartx, charttop, chartw, charth = 101, 250, 702, 300
text('R$ milhões',64,210,16,MUTED)
for tick in [0,5,10,15,20]:
    yy=charttop+charth-charth*tick/20
    line(chartx,yy,chartx+chartw,col=RULE,width=.7)
    text(str(tick),64,yy-8,15,MUTED)
for i,(day,values) in enumerate(sorted(daily.items())):
    x=chartx+i*chartw/30+3
    acc=0
    for status in STATUSES:
        val=float(values[status])/1e6
        h=charth*val/20
        rect(x,charttop+charth-(acc*charth/20)-h,chartw/30-6,h,COLORS[status])
        acc+=val
    if i%2==0 or i==29:
        text(day[-2:],x-1,charttop+charth+12,12,MUTED)
lx=101
for status in STATUSES:
    rect(lx,601,12,12,COLORS[status]); text(status,lx+20,599,14,MUTED); lx+=145
line(844,206,844,618)
text('R$ 526,02 mi',888,213,37,INK,True,328)
text('R$ 526.021.301,72',890,262,18,MUTED)
for i,status in enumerate(['delivered','paid','shipped','cancelled','pending']):
    yy=310+i*43
    rect(889,yy+3,12,12,COLORS[status])
    text(status,913,yy,18,INK)
    text(fmt(totals[status]/TOTAL*100,1)+'%',1134,yy,19,INK,True)
para('Inclui cancelados.<br/><b>Não é receita reconhecida.</b>',889,542,328,21,ORANGE,maxh=65)
metrics = json.loads((FINAL / 'athena-metrics.json').read_text())
source(f"Consulta final: 150 grupos; {metrics['data_scanned_bytes']} bytes lidos; {metrics['total_execution_ms']} ms; sem reuso de resultado.")

start('Acesso separado por responsabilidade', 'IAM controla os objetos. Lake Formation governa o catálogo e o uso das localizações registradas.', '05  /  Governança')
table(['PAPEL','OBJETOS NO S3','CATÁLOGO / LAKE FORMATION'],[
    ['Ingestion','Carga em raw/orders/*','DATA_LOCATION_ACCESS na raw'],
    ['Pipeline','Lê raw, escreve trusted/refined<br/>e a quarentena','3 localizações; SELECT/DESCRIBE<br/>nas tabelas do projeto'],
    ['Analyst','Lê refined e usa os resultados<br/>do Athena','SELECT/DESCRIBE só na refined;<br/>sem leitura raw/trusted'],
], [180,462,510],y=206,size=21,rowh=78)
text('12',64,518,44,TEAL,True)
para('checagens funcionais reais<br/>6 analyst + 6 ingestion',151,522,330,20,maxh=70)
text('11',495,518,44,INK,True)
para('simulações IAM<br/>complementares',580,522,250,20,maxh=70)
para('<b>Verificação real:</b> grants exatos,<br/>sem compatibilidade ampla no banco.<br/>30 checks aprovados na AWS.',864,510,352,19,maxh=100)
source('fechamento-21-11-2026: access-matrix.json, ingestion-access.json e verification.txt. Chamadas reais separadas de simulações.')

start('Decisões e seus custos', 'O projeto privilegia reprodução e rastreabilidade. As escolhas têm limites explícitos.', '06  /  Engenharia')
table(['ESCOLHA','GANHO OBSERVADO','CUSTO OU LIMITE ACEITO'],[
    ['Grão: item vigente','174.878 linhas e chaves únicas','Versões anteriores ficam apenas na raw'],
    ['Partição por evento','Backfill reescreve um único dia','Releitura dos 187.854 eventos raw'],
    ['Parquet + agregação','46,54 MB raw; 5,58 MB trusted;<br/>50,86 KB refined','Redução inclui limpeza e deduplicação,<br/>não apenas compressão'],
    ['Schema no Terraform','Catálogo explícito, sem crawler','Mudança de schema exige revisão'],
], [295,405,452],y=206,size=20,rowh=72)
text('Athena: ~US$ 0,00005',64,568,26,TEAL,True)
text('por consulta, pelo mínimo de 10 MB',64,606,18,MUTED)
text('Glue: ~US$ 0,31',684,568,26,TEAL,True)
text('Histórico de 19/11: 11 runs; 2.556 DPU-s',684,606,18,MUTED)
source('DECISOES.md; métricas Athena; glue-cost-estimate-final.json. Estimativas, não fatura. Tarifas e exclusões no apoio 11.')

start('Resultado e limites da entrega', 'O pipeline responde à pergunta. As evidências distinguem o ciclo histórico da validação final.', '07  /  Fechamento')
heading('Medido na AWS em 19/11',64,210,550)
for i,(n,body) in enumerate([
    ('59 / 59','recursos removidos e recriados;<br/>backend preservado e plano sem mudanças'),
    ('150 / 150','grupos da consulta conferidos também<br/>por recálculo independente'),
    ('1 / 30','partição reescrita no backfill;<br/>29 outras preservadas em cada camada')]):
    yy=265+i*112
    text(n,64,yy,35,TEAL,True)
    para(body,236,yy,382,20,maxh=80)
    line(64,yy+88,618)
heading('Validação final - 21/11',684,210,532)
para(f"<b>{validation['unit_tests']} testes unitários + 10 Spark.</b><br/>Quarentena vazia, desempates, backfill,<br/>hashes e falhas operacionais cobertos.",684,264,532,22,maxh=110)
para('<b>AWS:</b> FULL, idempotência, backfill e acessos<br/>revalidados; plano sem diferenças.<br/>Conta dedicada: roteiro, sem ensaio real.',684,397,532,21,maxh=100)
para('<b>Reprodução:</b> código, decisões e evidências<br/>versionados; consulta com custo, idempotência,<br/>backfill e remoção documentados.',684,526,532,21,maxh=90)
source('Ciclo de recriação: 19/11. Revisão final: evidencias/av2/brutas/fechamento-21-11-2026/validacao-final.json.')

start('Modelo analítico e consulta', 'Apoio para perguntas. A agregação acontece no Glue; o SQL lê a tabela final filtrada por data.', 'A1  /  Modelo e SQL')
heading('Uma linha por dia e status',64,210,530)
table(['COLUNA','DEFINIÇÃO'],[
    ['order_date','Data do pedido, partição'],['status','5 estados do pedido (página 5)'],
    ['order_count','COUNT(DISTINCT order_id)'],['item_count','COUNT(*) de itens vigentes'],
    ['quantity_total','SUM(quantity)'],['gross_sales','SUM(quantity × unit_price)']
], [204,350],y=251,size=18,rowh=50)
heading('Consulta executada',684,210,530)
sql=(ROOT/'consultas/av2-valor-bruto.sql').read_text().strip()
rect(684,251,532,320,INK)
for i,s in enumerate(sql.splitlines()):
    text(s,706,273+i*24,16,WHITE,maxw=488)
para('150 linhas = 30 datas × 5 status.<br/>Contagem de pedidos é por grupo. Não some<br/>grupos como se fossem clientes únicos.',684,580,532,17,maxh=65,leading=21)
source('consultas/av2-valor-bruto.sql; pipeline_orders.py (groupBy); catalog.tf; fechamento-21-11-2026/athena-results.json.')

start('Regras de tratamento e chegadas tardias', '185.938 itens base, 1.916 reentregas e 10.861 eventos normalizáveis plantados. Exemplos ilustrativos abaixo.', 'A2  /  Qualidade em detalhe')
table(['ENTRADA','TRATAMENTO','RESULTADO'],[
    ['" PAID " e UF "pe"','trim + caixa padronizada','paid e PE'],
    ['Preço "1234,50"','Vírgula para ponto; decimal(10,2)','1234.50'],
    ['Quantidade 0, UF ZZ,<br/>data inválida ou chave vazia','Rejeição antes da deduplicação','Parquet em raw/quality/rejected/'],
    ['Mesma chave pedido + item','Ordena updated_at, arrival_date,<br/>SHA-256, todos decrescentes','Uma versão vigente na trusted'],
], [345,400,407],y=205,size=20,rowh=72)
heading('Chegada e evento são datas distintas',64,553,650)
para('Até 6 dias de atraso, incluindo reentregas. A raw guarda arrival_date;<br/>trusted/refined usam order_date. O backfill relê a fonte para recuperar o dia.',64,590,1152,18,maxh=52)
source('generate_raw.py; pipeline_orders.py. Quarentena por modo é snapshot e não contém uma coluna textual de motivo.')

start('Tempos de execução e estimativas', 'Ciclo histórico de 19/11 em us-east-1. Não inclui os novos testes de 21/11 nem representa a fatura total.', 'A3  /  Desempenho e custo')
table(['EXECUÇÃO PÓS-RECRIAÇÃO','DURAÇÃO','CONSUMO'],[
    ['FULL 1','141 s','282 DPU-s'],['FULL 2','128 s','256 DPU-s'],['BACKFILL de 15/09','107 s','214 DPU-s']
], [350,200,220],x=64,y=210,size=22,rowh=64)
para('<b>3 execuções:</b> 752 DPU-s ÷ 3.600 × US$ 0,44 = <b>US$ 0,0919</b><br/><b>11 execuções capturadas:</b> 2.556 DPU-s = <b>US$ 0,3124</b>',64,466,770,21,maxh=75)
para('Exclui S3, CloudWatch, Athena e runs não capturados.<br/>O conjunto de 11 inclui as oito execuções históricas anteriores.',64,569,770,19,MUTED,maxh=65)
line(869,210,869,624)
heading('Consulta Athena',905,210,310)
text('10.060',905,269,40,TEAL,True)
text('bytes examinados',905,317,19,MUTED)
para('1.115 ms no total<br/>977 ms de engine<br/>Sem resultado reutilizado',905,369,311,20,maxh=90)
para('US$ 5/TB, mínimo 10 MB.<br/><b>Estimativa: US$ 0,00005.</b><br/>Meta &lt; 1 MiB atendida.<br/>Teto do workgroup: 10 MiB.',905,498,311,19,maxh=110)
source('glue-cost-estimate-final.json; athena-20261119T032256Z-metrics.json; AWS Glue Pricing e Athena Pricing (19/11/2026).')
c.linkURL('https://aws.amazon.com/glue/pricing/',(64,53,628,75),relative=0,thickness=0)
c.linkURL('https://aws.amazon.com/athena/pricing/',(630,53,1216,75),relative=0,thickness=0)

start('Reprodução e mapa de evidências', 'Arquivos do repositório permitem conferir os resultados. As capturas históricas permanecem preservadas.', 'A4  /  Rastreabilidade')
heading('Sequência de reprodução',64,205,550)
steps=[
    ('1. Preparar','Confirmar conta, usuário IAM e administrador LF.<br/>Backend separado; workspace fora de default.'),
    ('2. Planejar','Validar Terraform e revisar o plano.<br/>Módulo revisado usa 36 blocos moved.'),
    ('3. Executar','Restringir compatibilidade LF; carregar raw.<br/>FULL, idempotência, backfill e consulta.'),
    ('4. Conferir','Acessos, grants exatos, hashes e inventário.<br/>Conta dedicada possui procedimento opt-in.')]
for i,(h,b) in enumerate(steps):
    yy=254+i*91
    text(h,64,yy,21,INK,True)
    para(b,64,yy+29,554,18,MUTED,maxh=51)
heading('Em brutas/fechamento-21-11-2026/',684,205,532)
e=[('Qualidade','full-report.json; unit-tests.txt<br/>spark-tests.txt'),
   ('Idempotência e backfill','idempotency.json<br/>backfill-report.json; backfill-isolation.json'),
   ('Negócio e desempenho','athena-results.json<br/>athena-metrics.json'),
   ('Infraestrutura e acesso','verification.txt; access-matrix.json<br/>no-drift.txt; ingestion-access.json')]
for i,(h,b) in enumerate(e):
    yy=254+i*91
    text(h,684,yy,20,INK,True)
    para(b,684,yy+29,532,17,MUTED,maxh=51)
source('README.md; parte-2/README.md; DECISOES.md; REVISAO-AV2.md. Execução em conta limpa continua sem prova real.')

c.save()
(HERE/'layout.json').write_text(json.dumps(layouts, ensure_ascii=False, indent=2))
(HERE/'chart-data.json').write_text(json.dumps({'rows':rows,'totals':{k:str(v) for k,v in totals.items()},'grand_total':str(TOTAL)},ensure_ascii=False,indent=2))
print(json.dumps({'pdf':str(OUT),'pages':page,'chart_rows':len(rows),'total':str(TOTAL)}))
