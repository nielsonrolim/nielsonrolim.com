# Revisão de qualidade dos resumos

Use este roteiro para comparar mudanças de prompt/modelo com **10–20 recortes reais**. Ainda não há uma amostra real avaliada neste repositório: os testes automatizados usam exemplos fictícios, rodam offline e verificam o fluxo, não a fidelidade semântica do modelo.

1. Separe 10–20 recortes: textos completos e trechos apenas do RSS; artigos em pt-BR e en-US; opiniões, previsões, dados numéricos e artigos longos. Registre a URL ou ID, o texto-fonte efetivamente disponível (`source_text` ou `entry.summary`), os dois resumos e se a fonte era parcial. Não copie textos ou dados de assinantes para o repositório.
2. Antes de mudar um prompt/modelo, guarde uma amostra dos resumos existentes fora do repositório. Depois gere novamente os mesmos recortes pela interface de edição e guarde a nova saída. **A geração explícita sobrescreve resumos editados à mão**: use cópias ou recortes descartáveis se precisar preservá-los. Não execute o CLI do modelo nos testes.
3. Leia cada fonte e avalie **separadamente pt-BR e en-US**, antes e depois, com a escala abaixo. Para fontes parciais, avalie somente contra o trecho disponível, nunca contra conclusões que ele não contém.

| Critério | 0 | 1 | 2 |
| --- | --- | --- | --- |
| Fidelidade | Inventa ou inverte afirmações, apresenta opinião como fato, perde ressalvas | Essencial correto, mas com simplificações que alteram nuances | Afirmações, números, ressalvas e grau de certeza fiéis à fonte |
| Informação concreta | Genérico ou recheado de inferências | Traz parte dos fatos relevantes | Prioriza fatos/exemplos sustentados pela fonte, sem preencher lacunas |
| Clareza | Confuso, repetitivo ou em tom de resenha | Compreensível, mas prolixo | Direto e legível, com extensão proporcional ao texto disponível |
| Tradução | Distorce o significado entre idiomas | Mantém a ideia central, perde nuances | Título e resumo naturais, com os mesmos fatos e ressalvas nos dois idiomas |

Registre uma linha por **recorte × idioma × versão**, com `ID/URL`, `fonte completa?`, `idioma`, `versão`, as quatro notas (0–2) e um comentário citando o trecho que justifica um 0 ou 1. Conte separadamente quantos resumos introduzem afirmações não sustentadas e quantos trechos de RSS são apresentados sem o aviso de fonte parcial.

Compare a distribuição das notas e os erros graves antes/depois. **Não aprove** uma mudança que aumente invenções ou transforme previsões em fatos, mesmo que sua média de clareza suba. Uma revisão humana é necessária: testes de prompt e formatação não demonstram melhora factual por si só.
