# Dados de demonstração

`pedidos.csv` é o único arquivo carregado na tabela `trusted`. Ele contém 12
pedidos sintéticos, sem nomes, endereços, e-mails, telefones ou credenciais. Os
identificadores de cliente são fictícios e existem apenas para demonstrar o
schema.

`exemplos-sujeira.csv` é deliberadamente inválido e **não é carregado** pelo
Terraform. Ele documenta problemas plausíveis que uma etapa anterior de
qualidade deveria impedir:

- linhas 2 e 3: duplicata exata de `order_id`;
- linha 4: status em caixa diferente (`PAID`);
- linha 5: status desconhecido (`shippedd`);
- linhas 6 e 7: quantidade zero ou negativa;
- linha 8: preço negativo;
- linha 9: timestamp em formato incompatível;
- linha 10: timestamp e preço malformados.

Separar esses exemplos preserva a demonstração dos casos de qualidade sem
quebrar a consulta principal da AV1.
