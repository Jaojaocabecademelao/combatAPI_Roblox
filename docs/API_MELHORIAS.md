# Visão de evolução da CombatAPI

## Para que serve este documento

Este documento descreve maneiras pelas quais a CombatAPI poderia se tornar
mais fácil de usar, entender, testar e integrar a jogos de luta no Roblox. Ele
não é um manual de funcionalidades existentes, nem uma lista de tarefas já
aprovadas. As ideias são propostas para discussão de arquitetura e produto.

As propostas não foram limitadas pela dificuldade de implementação. A pergunta
que orienta o texto é: **se a API pudesse oferecer uma experiência ideal para
quem cria e mantém sistemas de combate, que responsabilidades e ferramentas
seriam úteis?**

O foco é uma infraestrutura que os jogos possam compor. A CombatAPI não
precisaria fornecer personagens, comandos, animações ou regras de balanceamento
prontas para todos os jogos. Ela deveria tornar mais simples declarar essas
regras, executá-las, conectá-las a outros sistemas e descobrir por que um
resultado aconteceu.

## Como ler as propostas

Cada seção descreve uma direção possível, explica o problema que pretende
resolver e dá exemplos do que um jogo ou desenvolvedor poderia fazer com ela.
Quando aparece código, ele é **pseudocódigo ilustrativo**: os nomes e métodos
mostram uma forma de uso desejável, não uma promessa de que a API já os
implementa.

As propostas partem da arquitetura documentada atualmente, mas não afirmam que
todo sistema mencionado já oferece as garantias descritas. Em especial,
rollback, determinismo, autoridade e compatibilidade dependem do estado e das
integrações que participam de cada partida. Os contratos atuais continuam
sendo a referência para o comportamento existente.

## Ponto de partida: o que a API já representa

A CombatAPI organiza o combate em torno de `World`, entidades, componentes,
resolvers, eventos e uma `Simulation` de passo fixo. Em termos simples:

- **World** reúne as entidades e os sistemas de uma instância de combate;
- **entidade** identifica algo que participa do mundo, como um personagem ou
  projétil;
- **componente** guarda um tipo de estado, como vida, input ou defesa;
- **resolver** aplica uma operação ou regra, como dano ou defesa;
- **evento** comunica um fato que aconteceu, em vez de pedir uma ação;
- **Simulation** avança o mundo em passos de jogo identificados por frame.

Esse desenho permite usar partes separadas da API em vez de adotar um sistema
monolítico. Também significa que um jogo pode precisar conectar várias peças:
capturar input, escolher uma ação, mover uma entidade, atualizar hitboxes,
processar contatos, aplicar resultados e apresentar efeitos.

A `CollisionWorld` trata os contatos entre hitboxes e hurtboxes registrados
na CombatAPI. Ela não é, por si só, uma representação de todo o mapa nem um
substituto da física de `Workspace`. Da mesma forma, avançar a `Simulation` em
passo fixo não torna reproduzíveis automaticamente chamadas a `Workspace`,
`Assembly` ou qualquer outro estado externo.

## Princípios desejáveis

1. **Responsabilidade explícita:** deve ser fácil saber qual sistema decide
   cada resultado de gameplay.
2. **Reprodução:** inputs e fatos externos relevantes devem poder ser
   registrados para investigar e, quando suportado, reproduzir uma partida.
3. **Separação de camadas:** regras do combate não devem depender
   implicitamente de objetos Roblox, renderização ou transporte de rede.
4. **Configuração legível:** ações e regras devem ser fáceis de ler, validar,
   versionar e comparar.
5. **Composição:** jogos devem poder usar a fachada de alto nível ou continuar
   chamando sistemas menores diretamente.
6. **Diagnóstico:** uma configuração ou operação recusada deve explicar o que
   aconteceu e apontar o dado relevante.
7. **Garantias honestas:** suporte a prediction, rollback ou determinismo deve
   ser declarado para a combinação real de sistemas em uso.
8. **Desempenho observável:** custo e limites devem poder ser medidos por
   sistema e por frame.

## 1. Descrever ações de combate declarativamente

### O que significa “declarativo”

Uma descrição declarativa registra **o que uma ação significa**: seus tempos,
requisitos, custos, regiões de acerto, cancelamentos e consequências. O jogo
fornece essa definição como dados. Um executor interpreta os dados nos frames
adequados.

Isso é diferente de espalhar a definição da ação por vários callbacks com
instruções imperativas como:

1. esperar alguns frames;
2. criar uma hitbox;
3. esperar mais frames;
4. verificar se houve acerto;
5. permitir ou negar o próximo comando;
6. remover a hitbox e terminar a ação.

Callbacks continuam úteis para comportamentos que realmente são específicos
do jogo. A melhoria seria permitir que as regras comuns de uma ação fossem
descritas de forma centralizada e inspecionável, em vez de depender de uma
sequência de código que precisa ser reconstruída mentalmente.

### Exemplo conceitual

Considere um golpe especial que custa recurso, tem preparação, cria um
projétil, pode ser cancelado após confirmar um acerto e termina em recuperação.
Uma definição possível poderia dizer:

```lua
local fireball = Action.define({
    Id = "fighter.special.fireball",
    Version = 1,

    Requirements = {
        Grounded = true,
        Resources = { Meter = 25 },
        Input = { "Down", "Forward", "Special" },
    },

    Costs = {
        Resources = { Meter = 25 },
    },

    Timeline = {
        StartupFrames = 10,
        ActiveFrames = 1,
        RecoveryFrames = 24,
    },

    OnActive = {
        SpawnProjectile = "projectile.fireball",
    },

    Cancels = {
        {
            From = "HitConfirm",
            To = { "Super", "Dodge" },
        },
    },
})
```

Esse exemplo não afirma que `Action.define`, `Requirements.Grounded` ou
`SpawnProjectile` existem hoje. Ele ilustra a intenção: os dados deixam
visíveis as condições para começar, o custo, a duração e os resultados
esperados da ação.

### Como isso poderia funcionar durante a partida

Uma sequência de uso ideal seria:

1. O desenvolvedor registra a definição de `fireball` em um catálogo de ações.
2. Antes da partida, a API valida os campos, referências, faixas de frame e
   existência do recurso `Meter`.
3. Durante a partida, o jogo envia o pedido do jogador para iniciar a ação.
4. O executor verifica input, estado do personagem e recurso disponível.
5. Se o pedido for aceito, o executor registra um estado da ação associado à
   entidade e ao frame inicial.
6. Em cada frame fixo, a ação avança sua timeline. No frame ativo, solicita a
   criação do projétil; nos frames de recuperação, aplica as regras de
   cancelamento configuradas.
7. O sistema de colisão e os resolvers existentes continuam determinando
   contatos, defesa, dano e consequências.
8. Eventos informam fatos observáveis, como início, cancelamento, acerto ou
   término da ação.

O executor não deveria substituir dano, colisão, defesa ou outros sistemas
especializados. Sua função seria coordenar a definição da ação com esses
sistemas.

### Validação e mensagens de erro

Uma definição deveria poder ser validada sem iniciar uma partida. Por exemplo,
se o golpe referencia um projétil inexistente ou cobra um recurso que não está
no catálogo do personagem, a validação poderia apontar o caminho e a causa:

```text
fighter.special.fireball.OnActive.SpawnProjectile:
  referência "projectile.fireball" não encontrada no catálogo
```

O relatório também poderia indicar valores contraditórios: duração negativa,
frame ativo fora da timeline, custo maior que o limite configurado ou uma
regra de cancelamento sem origem válida.

### Relação com a API atual

A API atual já possui definições e perfis de ação, incluindo exemplos como
`CombatActionProfiles.Projectile()`. Uma evolução declarativa poderia
aprofundar esse conceito e conectar mais regras da ação à timeline. Isso não
significa que os perfis atuais já controlem movimento, hitboxes ou projéteis:
as responsabilidades e os limites de cada contrato precisam continuar
explícitos.

### Primeiro incremento: eventos declarativos da timeline

O primeiro incremento usa handlers de gameplay já registrados, sem introduzir
um executor de projéteis, hitboxes ou dano. Uma definição pode declarar eventos
serializáveis associados a frames da sua timeline:

```lua
local fireball = CombatAPI.CombatActionDefinition.new({
    Id = "fighter.special.fireball",
    StartupFrames = 10,
    ActiveFrames = 1,
    RecoveryFrames = 24,
    GameplayEvents = {
        {
            FrameOffset = 10,
            Type = "combat.projectile.spawn.v1",
            Parameters = { ProjectileId = "projectile.fireball" },
        },
    },
})
```

Contrato inicial:

- `FrameOffset` é um inteiro positivo relativo ao `StartFrame`; o handler é
  chamado sincronicamente durante `World:Step`, antes de a ação avançar sua
  fase naquele frame. Eventos no mesmo frame mantêm a ordem declarada.
- A definição é validada na construção: offsets devem caber na duração de uma
  ação finita; tipo do evento precisa ser um identificador válido; parâmetros
  devem ser uma tabela serializável sem metatable, funções ou referências
  Roblox. A API guarda cópia congelada dos parâmetros.
- Antes do registro da definição/catálogo no pipeline, cada `Type` precisa ter
  um handler registrado com `World:RegisterGameplayActionEventHandler`. Uma
  referência ausente é reportada com o caminho da definição, antes de a ação
  poder começar.
- O handler recebe `Type`, `Frame`, `OwnerId`, `Parameters`, `ActionId`,
  `ActionDefinitionId` e `EventIndex`. Ele integra a ação aos sistemas do jogo;
  a CombatAPI não assume como criar um projétil ou alterar uma hitbox.
- O handler executa durante replay quando a restauração avança novamente pelo
  frame declarado. Portanto, deve alterar apenas estado autoritativo
  restaurável e não deve depender de relógio real, aleatoriedade externa ou
  efeitos de apresentação.
- O catálogo inclui os eventos no manifest. Manifestos antigos sem eventos
  continuam válidos apenas quando as definições atuais também não declaram
  eventos; conteúdo divergente deve ser rejeitado.

Pseudocódigo do executor:

```lua
for effectIndex, effect in ipairs(action.Definition.GameplayEvents) do
    local targetFrame = action.StartFrame + effect.FrameOffset
    if action.CurrentFrame < targetFrame and targetFrame <= frame then
        simulation:_DispatchGameplayActionEvent(effect.Type, {
            Type = effect.Type,
            Frame = targetFrame,
            OwnerId = action.Owner.Id,
            Parameters = effect.Parameters,
            ActionId = action.Id,
            ActionDefinitionId = action.Definition.Id,
            EventIndex = effectIndex,
        })
    end
end
action:Advance(frame)
```

Critérios de aceite deste incremento: validação recusa offsets e parâmetros
inválidos, o pipeline recusa handlers ausentes antes do início, os handlers
recebem eventos no frame/ordem esperados, e replay após restaurar um snapshot
reproduz os mesmos efeitos sem repetir eventos anteriores ao snapshot.

**Benefício esperado:** movimentos complexos ficam mais fáceis de revisar,
balancear, testar e mostrar em ferramentas, sem retirar do jogo a opção de
usar componentes e resolvers diretamente.

## 2. Tornar a colisão de combate mais expressiva

### Problema que se pretende resolver

Um ataque pode atravessar uma região entre dois frames se sua posição mudar
muito rapidamente e a colisão só comparar a posição inicial ou final. Em
outros casos, o jogo precisa distinguir partes do corpo, filtrar quais grupos
podem colidir ou saber se um contato começou, continuou ou terminou.

Uma API de colisão mais completa deveria expressar essas diferenças sem
obrigar todos os jogos a adotar as mesmas regras de personagem ou de cenário.

### Capacidades possíveis

- **Colisão varrida:** considerar o percurso de uma forma entre a posição
  anterior e a atual, em vez de testar apenas um ponto por frame. Isso ajuda a
  detectar golpes ou projéteis rápidos que cruzam um alvo entre atualizações.
- **Grupos e máscaras:** identificar categorias como ataque, corpo, escudo e
  cenário, e configurar quais pares podem interagir.
- **Regiões nomeadas:** distinguir cabeça, tronco, pernas, escudo ou outras
  regiões para regras como dano especial, invulnerabilidade ou reação.
- **Ordem de resolução:** declarar como tratar vários contatos no mesmo frame,
  por exemplo, dois ataques que acertam simultaneamente.
- **Ciclo do contato:** publicar quando um contato começou, permaneceu ativo
  ou terminou, em vez de expor somente um resultado isolado.
- **Consultas auxiliares:** oferecer formas claras de perguntar por
  proximidade, volume ocupado ou linha de visão quando o jogo precisar dessas
  informações.
- **Escala espacial:** permitir que o sistema limite candidatos próximos antes
  de testar formas, mantendo a semântica dos resultados definida.

### Declarar o domínio de cada consulta

Toda consulta deveria informar de onde vem a geometria usada:

1. **Interna e determinística:** posições e formas mantidas no estado de
   combate.
2. **Externa e capturada:** resultado fornecido por um adaptador e registrado
   para o frame.
3. **Somente visual ou informativa:** consulta que não decide dano ou outro
   resultado autoritativo.

Essa distinção impede que uma consulta de conveniência seja confundida com
uma garantia de determinismo ou rollback.

**Benefício esperado:** jogos podem expressar colisões de forma mais precisa e
investigar contatos sem esconder a origem dos dados geométricos.

## 3. Padronizar consultas de cenário e reprodução de resultados externos

### Por que isso é diferente da colisão entre lutadores

Uma hitbox da CombatAPI pode ser testada contra uma hurtbox registrada no
estado do combate. Já uma parede, plataforma móvel ou peça física costuma
existir em `Workspace` e ser consultada por uma API do Roblox. O estado dessa
geometria pode mudar fora da `Simulation`.

Por isso, não basta repetir a mesma chamada a `Spherecast` durante rollback:
a posição ou forma do mapa pode já ser diferente. Para reconstruir uma decisão
passada, é necessário reproduzir **o resultado que foi usado naquele frame**,
ou representar o cenário em um modelo determinístico próprio.

### Dados que um adaptador deveria registrar

Para cada consulta que afete gameplay, o contrato poderia registrar:

- frame de simulação e ordem da consulta naquele frame;
- identificador estável da consulta e versão do adaptador;
- posição inicial, forma, raio ou dimensões, direção e filtros;
- identidade ou versão da geometria consultada;
- se houve contato;
- distância, posição, normal e identificador estável do objeto atingido;
- decisão de jogo que consumiu o resultado, se for necessária para diagnóstico;
- comportamento definido para resultado ausente ou incompatível.

O registro é a entrada histórica que torna a decisão compreensível; ele não é
uma promessa de que a física do Roblox possa ser restaurada.

### Fluxo esperado

1. No frame `N`, a lógica autoritativa solicita uma consulta identificada.
2. O adaptador do servidor executa a consulta sobre a geometria apropriada.
3. O adaptador converte o resultado em dados estáveis, sem guardar uma
   referência transitória a uma `Instance` como única fonte de verdade.
4. O resultado é associado ao frame e fica disponível à simulação.
5. Se ocorrer rollback até o frame `N`, a simulação recupera o resultado
   registrado para aquela consulta, em vez de consultar o mapa atual novamente.
6. Se o registro não existir ou sua versão não corresponder, a API informa a
   incompatibilidade e aplica uma política explícita — por exemplo, recusar a
   reprodução em vez de inventar um resultado.

**Importante:** executar `Workspace:Spherecast` dentro de um passo fixo não
torna a consulta determinística. A execução continua dependendo do estado
externo consultado.

## 4. Oferecer movimento reproduzível para projéteis e objetos

### Estado de gameplay e representação visual são coisas diferentes

Um projétil pode ter um estado lógico que decide onde ele está para o combate,
e uma peça Roblox que mostra sua aparência na tela. Esses objetos estão
relacionados, mas não são a mesma responsabilidade:

- o **estado autoritativo** contém posição, velocidade, direção, tempo de vida
  e outras propriedades necessárias às regras;
- a **representação Roblox** é uma `Part`, modelo ou efeito visual atualizado
  para mostrar esse estado;
- a **consulta ambiental** detecta contato com o mapa e deve seguir o contrato
  de geometria externa se influenciar gameplay;
- a **hitbox** participa das regras de contato entre entidades da CombatAPI.

Separar essas funções permite restaurar o estado de combate sem tratar a
instância visual como o registro histórico da partida.

### Movimento que poderia ser configurado

Uma definição opcional de movimento poderia incluir posição inicial,
velocidade, aceleração, limites máximos, arrasto e integração por frame.
Políticas de contato poderiam ser escolhidas pelo jogo: parar, refletir,
ricochetear, atravessar, perder velocidade, retornar ao lançador ou terminar.

Uma arma presa por corda também poderia usar um modelo de vínculo configurável
para comprimento, ponto de ancoragem e resposta ao exceder esse comprimento.
Isso deveria ser uma composição opcional — não uma regra universal para todos
os projéteis ou uma dependência direta de `Workspace`.

### Exemplo da divisão de responsabilidades

Em cada frame, um sistema de movimento poderia atualizar a posição lógica. O
jogo pediria ao adaptador Roblox para mostrar a peça nessa posição. Se o objeto
passasse perto de uma parede, o adaptador forneceria o resultado capturado da
consulta ambiental. A regra configurada decidiria se o projétil ricocheteia ou
termina; a hitbox atualizada continuaria verificando contatos com hurtboxes.

**Benefício esperado:** o jogo teria menos código repetido para movimento
comum, sem perder controle sobre a política de cada arma.

## 5. Criar uma timeline visual e ferramentas de autoria

Uma timeline é uma representação da ação organizada por frame. Em vez de
procurar em vários scripts quando uma hitbox aparece, o desenvolvedor poderia
visualizar uma faixa de tempo com:

- frames de preparação, atividade e recuperação;
- início e fim de cada hitbox;
- movimento ou criação de projéteis;
- janelas de cancelamento;
- custos, eventos e condições especiais;
- contatos que realmente ocorreram durante uma simulação de teste.

Uma ferramenta no Roblox Studio poderia desenhar as regiões ao lado da
animação, avançar frame a frame e comparar o plano da ação com a execução
observada. Isso ajudaria a responder perguntas como “a hitbox está ativa no
frame correto?” ou “o cancelamento foi permitido antes do fim da recuperação?”.

As definições editáveis deveriam ser separadas do estado temporário de uma
partida. Ao começar a partida, o jogo poderia carregar uma versão imutável do
catálogo para que mudanças feitas no editor não alterassem uma partida em
andamento.

**Benefício esperado:** criar, revisar e balancear ações deixa de depender
somente da leitura de código ou de tentativa e erro em partidas completas.

## 6. Coordenar rede, predição, rollback e reconciliação

### O problema em termos simples

Em uma partida pela rede, os jogadores não enviam uma posição final confiável
para o adversário. Eles enviam inputs, e cada lado precisa decidir em que frame
esses inputs pertencem, o que simular enquanto espera e como corrigir o estado
quando chega informação atrasada ou diferente.

Uma camada de sessão de combate poderia coordenar as ferramentas de rede e
simulação da API para que o jogo não precise inventar um protocolo diferente
para cada projeto.

### O que a camada precisaria especificar

- Quem pode propor um input e quem confirma que ele foi aceito.
- Como associar input ao jogador, entidade e frame.
- O que fazer quando o input chega atrasado, duplicado ou fora de ordem.
- Como decidir quantos frames prever enquanto a confirmação não chega.
- Como restaurar o estado anterior e simular novamente após uma correção.
- Como comunicar aos participantes o frame confirmado e as divergências.
- Quais sistemas e adaptadores realmente podem ser restaurados.
- Como tratar efeitos que não podem ser “desfeitos”, como recompensa, som ou
  analytics.

Por exemplo, um efeito visual especulativo de um golpe previsto poderia ser
cancelado se o servidor rejeitar a ação. Uma recompensa, ao contrário, poderia
esperar pela confirmação antes de ser concedida.

O transporte continuaria intercambiável: a camada de combate não deveria
depender diretamente de um `RemoteEvent` específico nem tratar a propriedade
de uma peça Roblox como prova de que uma ação foi autorizada.

**Benefício esperado:** integração de rede mais uniforme e menos ambiguidade
sobre o que foi previsto, confirmado ou corrigido.

## 7. Validar o estado restaurável e diagnosticar determinismo

Para restaurar um combate, não basta salvar a posição dos personagens. Também
podem importar recursos, timers, estados de ações, histórico de acertos,
estado da simulação e resultados externos usados por regras.

Uma melhoria seria exigir que cada extensão que altera gameplay informe como:

1. captura seu estado;
2. valida se consegue restaurar o estado recebido;
3. prepara a restauração sem efeitos colaterais indevidos;
4. identifica a versão do formato salvo.

Antes de habilitar rollback, um relatório poderia listar quais sistemas estão
prontos, quais dependem de entradas externas registradas e quais impedem uma
restauração completa. Assim, o jogo não precisaria descobrir uma incompatibilidade
no meio de uma correção de rede.

Um diagnóstico de determinismo poderia indicar o frame e a extensão
associados a problemas como:

- uso de relógio real em uma decisão de gameplay;
- sorteio sem gerador determinístico;
- iteração cuja ordem muda entre execuções;
- estado autoritativo que não foi incluído no snapshot;
- consulta externa feita novamente durante replay;
- hash de estado diferente do esperado;
- formato de snapshot incompatível com a versão carregada.

O objetivo não é proibir todo uso de serviços externos. É distinguir o que
pode decidir gameplay e garantir que os dados necessários estejam disponíveis
quando a partida for reproduzida.

## 8. Separar apresentação, interpolação e efeitos

Uma posição autoritativa pode chegar em intervalos discretos, enquanto a tela
é atualizada continuamente. O cliente pode suavizar a exibição entre posições
recebidas, mas essa suavização não deve alterar a posição usada para decidir
acertos ou dano.

Uma camada de apresentação poderia receber estados e eventos confirmados e
coordenar:

- interpolação visual de personagens e projéteis;
- animações, partículas, sons e câmera;
- correções graduais quando a posição confirmada divergir da exibição;
- efeitos especulativos relacionados a inputs ainda não confirmados.

Cada efeito especulativo precisaria de uma identidade estável e de uma política
clara: manter após confirmação, cancelar após rejeição ou substituir por uma
apresentação corrigida.

**Distinções importantes:**

- **Interpolação** suaviza a exibição entre estados conhecidos.
- **Predição** estima um estado futuro antes de receber confirmação.
- **Reconciliação** corrige a predição usando informação autoritativa.
- **Colisão autoritativa** decide resultados de gameplay.

Esses conceitos podem colaborar, mas não devem compartilhar acidentalmente a
mesma posição ou modificar uns aos outros.

## 9. Versionar catálogos e conteúdo de combate

Um catálogo reúne definições que o jogo usa durante uma partida: personagens,
ações, recursos, regras de estado e outros dados de combate. Um sistema formal
de catálogos poderia ajudar a:

- atribuir identificadores e versões estáveis;
- verificar referências entre ações, projéteis e recursos;
- validar valores e limites antes de iniciar a sessão;
- criar templates ou variantes sem alterar a definição-base
  silenciosamente;
- comparar duas versões e mostrar quais frames, custos ou regras mudaram;
- registrar qual conjunto de conteúdo foi usado numa partida.

Esse último dado é importante para replay: os mesmos inputs podem produzir
resultados diferentes se o custo ou a duração de um golpe mudou depois da
partida original. Associar um identificador ou fingerprint ao conteúdo
permite saber qual definição deve ser carregada.

Migrações explícitas também ajudariam quando o formato de um catálogo mudar.
Uma versão antiga poderia ser convertida ou rejeitada com um diagnóstico, em
vez de ser interpretada silenciosamente com regras novas.

## 10. Declarar capacidades e restrições de extensões

Plugins e adaptadores podem ter responsabilidades muito diferentes. Um
adaptador de partículas pode apenas apresentar eventos; um plugin de gameplay
pode alterar recursos ou estados que afetam o resultado da partida.

Uma extensão poderia declarar:

- quais sistemas usa e quais operações pode realizar;
- se altera estado autoritativo ou apenas apresentação;
- se suporta execução normal, prediction, replay e rollback;
- qual estado precisa salvar e qual versão de contrato requer;
- quais dependências precisam estar disponíveis.

Antes de iniciar uma partida, a API poderia comparar essas declarações com as
capacidades da sessão. Se um plugin alterar estado autoritativo, mas não puder
capturá-lo para rollback, a incompatibilidade poderia ser mostrada ao
desenvolvedor antes de uma partida competitiva.

Isso não seria um mecanismo para executar código desconhecido sem confiança.
Seria uma forma de tornar explícitas as garantias e responsabilidades das
extensões confiáveis usadas pelo jogo.

## 11. Gravar e inspecionar partidas

Um replay útil precisa de mais do que uma gravação de vídeo. Para investigar
uma decisão, seria importante armazenar os inputs, frames, versões de conteúdo
e fatos externos relevantes para o gameplay, além de decisões e hashes de
estado escolhidos pelo jogo.

Uma ferramenta de inspeção poderia permitir ao desenvolvedor:

- carregar uma gravação e simular a partida localmente;
- pausar, avançar ou voltar frame a frame;
- ver inputs, ações e eventos presentes naquele frame;
- inspecionar por que um ataque acertou, errou, foi bloqueado ou cancelado;
- comparar duas execuções e destacar o primeiro frame divergente;
- transformar uma divergência em um teste que possa ser repetido após uma
  mudança no código.

O formato de gravação deveria incluir versões e permitir selecionar quais
dados registrar. Uma partida pode ter dados volumosos ou privados; o jogo deve
controlar retenção, acesso e nível de detalhe.

Logs detalhados também precisam ser opcionais ou limitados em produção. Ativar
diagnóstico não deveria mudar a lógica do combate nem alterar a ordem de
execução.

### Primeiro incremento: diagnóstico por frame e consulta de replay

Este incremento deve tornar os diagnósticos existentes mais acionáveis sem
interceptar operações do Roblox nem alterar a execução:

- Cada violação explícita do `DeterminismGuard` recebe um `Sequence` crescente
  durante a vida do guard e o `Frame` atual da simulação, além de `Operation`,
  `Context` e `Details`. `ClearViolations()` apaga os registros, mas não
  reinicia a sequência.
- `ReplayRecording:GetFrame(frame)` retorna uma cópia serializável do registro
  daquele frame. `GetFrameRange(firstFrame, lastFrame)` retorna cópias em uma
  lista densa, com limites inclusivos. Ambos recusam frames indisponíveis com
  códigos explícitos e nunca expõem tabelas internas.
- `FindFirstDivergence` continua retornando o primeiro frame e o motivo; em
  divergências de input, estado inicial ou fatos externos por frame, o detalhe
  inclui cópias dos valores esperado e observado para que um teste possa
  reproduzir o caso. Uma divergência somente de hash continua reportando os
  hashes; incompatibilidade do journal externo global continua sem frame
  associado. Não há snapshots completos por frame nesta mudança.
- O formato serializado do replay permanece na versão atual. Consultar dados
  ou habilitar esses diagnósticos não altera o estado de gameplay.

Pseudocódigo de inspeção:

```lua
local frame, reason = recording:GetFrame(frameNumber)
if frame == nil then
    error(("Replay frame unavailable: %s"):format(reason))
end

local frames, rangeReason = recording:GetFrameRange(firstFrame, lastFrame)
local divergenceFrame, detail = expected:FindFirstDivergence(actual)
```

O teste de aceite deve verificar sequência/frame/contexto das violações,
inclusive após limpar a lista, independência das cópias retornadas e valores
esperado/observado da primeira divergência. Comparar hashes continua sendo
responsabilidade do host; o guard continua sendo instrumentação explícita,
não uma interceptação global de relógio, aleatoriedade ou consultas externas.

## 12. Medir desempenho e declarar limites

Uma API pode estar correta em pequenos testes e ainda custar demais quando há
muitos personagens, hitboxes, efeitos ou frames de rollback. Para tornar
desempenho compreensível, a API poderia expor medições como:

- tempo ou custo de cada sistema por passo;
- número de pares de colisão testados e contatos encontrados;
- entidades e componentes ativos;
- tamanho e frequência de snapshots;
- quantidade de frames reprocessados em rollback;
- número de eventos produzidos e entregues.

O jogo poderia configurar limites para esses recursos e receber alertas quando
se aproximassem do orçamento escolhido. Um relatório deveria distinguir um
pico isolado de um custo persistentemente alto.

Otimizações, como agrupar consultas ou filtrar entidades distantes, deveriam
preservar os resultados e a ordem autoritativa definidos pelos contratos. Uma
melhoria de performance não deveria mudar silenciosamente quem acertou
primeiro.

## 13. Tornar testes e conformidade mais fáceis

Os testes de combate são mais úteis quando descrevem um cenário em termos de
frames e resultados esperados. Uma ferramenta de teste poderia permitir
especificar:

1. a configuração inicial do mundo;
2. os inputs e mudanças externas em cada frame;
3. os eventos ou resultados esperados;
4. os valores de estado que devem ser iguais após reprodução.

Por exemplo: “no frame 1, o jogador inicia o golpe; no frame 5, a hitbox fica
ativa; no frame 7, o oponente bloqueia; no frame 8, a recuperação começa”.
Se o resultado mudar, o teste poderia mostrar o primeiro frame em que o
resultado real divergiu do esperado.

Uma suíte de conformidade para adaptadores também poderia testar as mesmas
garantias em implementações diferentes: ordenação estável, captura e
restauração, comportamento com dados ausentes, limpeza de conexões e política
durante replay.

Uma estratégia de qualidade abrangente incluiria:

- testes unitários de cada resolver e componente;
- testes de integração entre sistemas que participam do mesmo fluxo;
- testes de limites, estados inválidos e invariantes;
- testes de repetição e comparação de estado;
- testes de rede com atraso, duplicação e reordenação;
- benchmarks com cenários representativos;
- exemplos executáveis no Roblox Studio.

## Limites que devem continuar explícitos

Mesmo que a API ofereça mais recursos, alguns limites precisam continuar
visíveis:

- A CombatAPI não deve ser apresentada como substituta da física completa do
  Roblox.
- Uma consulta externa refeita contra o estado atual do mapa não reconstrói
  necessariamente o resultado histórico.
- Um sistema não deve ser chamado de compatível com rollback se parte do seu
  estado autoritativo não puder ser restaurada.
- Interpolação visual não é previsão; previsão não é confirmação.
- O cliente pode solicitar ações, mas o servidor precisa validar o que é
  autoritativo conforme as regras do jogo.
- Adaptadores devem declarar as garantias e limitações que fornecem.
- O comportamento exato da implementação atual deve ser verificado na
  documentação e nos testes correspondentes; esta proposta não altera esses
  contratos por si só.

## Sequência conceitual de evolução

Esta ordem destaca dependências entre ideias; não representa uma estimativa de
esforço ou um compromisso de implementação:

1. Explicar e formalizar os contratos de estado, autoridade, execução e
   determinismo.
2. Definir como geometria e outros fatos externos são registrados e
   reproduzidos por frame.
3. Consolidar definições declarativas de ações, catálogos e validação.
4. Ligar essas definições às timelines, colisão e movimento de projéteis.
5. Coordenar inputs de rede, predição, rollback, confirmação e efeitos.
6. Construir ferramentas para autoria, visualização, gravação e inspeção no
   Studio.
7. Publicar métricas, limites e testes de conformidade para sistemas e
   adaptadores.

## Como saber se a evolução foi bem-sucedida

- Um desenvolvedor consegue entender uma ação complexa lendo sua definição,
  sem precisar localizar uma sequência de callbacks não relacionados.
- A ferramenta de validação aponta campos, referências e frames incorretos
  antes da partida.
- Uma gravação identifica quais inputs, conteúdo e fatos externos produziram
  uma decisão.
- Se duas execuções divergirem, o desenvolvedor consegue localizar o primeiro
  frame e o sistema responsável pela divergência.
- A documentação informa claramente quais partes são determinísticas,
  autoritativas, restauráveis ou somente visuais.
- Um jogo pode trocar o transporte ou a representação visual Roblox sem
  reescrever as regras de combate.
- O custo do combate pode ser medido por sistema e comparado com um orçamento.

## Relação com as propostas anteriores

As propostas anteriores de exemplo de projétil, consultas externas de
geometria e interpolação visual continuam contempladas. Este documento as
explica dentro de uma visão mais ampla:

- exemplo e movimento de projétil: seções 1 e 4;
- colisão e geometria do cenário: seções 2 e 3;
- replay, rede e estado restaurável: seções 6, 7 e 11;
- apresentação e interpolação: seção 8;
- autoria declarativa, validação e ferramentas: seções 1 e 5.

As referências abaixo descrevem a documentação atual do projeto. Consulte-as
para confirmar os contratos existentes antes de transformar uma proposta em
mudança de código.

## Referências

- [Documentação da CombatAPI](../CombatAPI/docs/README.md)
- [Integration boundaries](../CombatAPI/docs/Integration.md)
- [Examples](../CombatAPI/docs/Examples.md)
- [Core and deterministic simulation](../CombatAPI/docs/Core.md)
- [Rollback](../CombatAPI/docs/Rollback.md)
- [ADR-005 — Geometria autoritativa e física Roblox](../CombatAPI/docs/adr/ADR-005-authoritative-geometry.md)
