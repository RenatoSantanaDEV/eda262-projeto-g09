# Apresentação AV2

O arquivo atual para apresentação e envio é `apresentacao-parte-2-g09.pdf`.

Edição visual de 25/11/2026: módulo Terraform, backend S3/DynamoDB e workspace
explicitados no slide 2; quebras de linha ajustadas no slide 3; fechamento
do slide 8 focado na reprodução. Os dados e datas das evidências são os da
validação de 21/11 e do ciclo histórico de 19/11. São 12 páginas, sem texto
fora da página e com Arial incorporada. Conferência registrada em
`../evidencias/av2/brutas/revisao-25-11-2026/pdf-validation.json`.
Contém oito páginas de exposição e quatro de apoio para perguntas.
O roteiro de cinco minutos está em `roteiro-5min.md`; a duração precisa ser ensaiada.

O PDF incorpora Arial, tem texto selecionável, gráficos vetoriais e índice de
navegação. As barras diárias usam os 150 resultados preservados do Athena,
com soma decimal de R$ 526.021.301,72. As páginas 9 a 12 ficam para perguntas.
A página 8 distingue o ciclo histórico de recriação da validação final de 21/11.
O gráfico usa a consulta final; tempos e custos do apoio A3 estão explicitamente
identificados como medições históricas de 19/11.

## Fonte editável

`fontes/build_pdf.py` lê as evidências do repositório e gera o PDF.
Requer Python 3, reportlab e os arquivos Arial.ttf, Arial Bold.ttf e Arial Italic.ttf.
No Mac, usa `/System/Library/Fonts/Supplemental`. Em outro ambiente, informe
uma pasta com esses arquivos por `AV2_FONT_DIR`.

Da raiz do projeto:

```bash
python3 apresentacao/fontes/build_pdf.py . apresentacao/apresentacao-parte-2-g09.pdf
```

O PPTX anterior de oito páginas não é a fonte desta edição e não integra o
ZIP revisado. A cópia anterior foi preservada no diretório de trabalho da revisão.

## Preços de referência

- [AWS Glue Pricing](https://aws.amazon.com/glue/pricing/)
- [AWS Athena Pricing](https://aws.amazon.com/athena/pricing/)
- [Athena: mínimo por consulta](https://docs.aws.amazon.com/whitepapers/latest/big-data-analytics-options/amazon-athena.html)

Tarifas usadas para estimativas, não fatura comprovada.
