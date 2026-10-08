# Staging em uma instância Linux local

Esta configuração usa a branch staging e RAILS_ENV=production, com PostgreSQL,
worker, frontend HTTPS e Mailpit em containers. O Gemfile é compartilhado:
gems de development/test ficam fora da imagem. Os dados e segredos de staging
são independentes do desenvolvimento e da produção.

## Preparar a máquina

Use uma VM Ubuntu Server 24.04 LTS no Windows, com pelo menos 2 vCPU,
4 GB de RAM e 30 GB de disco como ponto de partida. A rede deve permitir acesso
do Windows à VM: use modo bridge/comutador externo e reserve um IP no roteador.
Não encaminhe portas do roteador para essa VM. Esses recursos não garantem
capacidade de produção; ajuste conforme consumo e carga.

Dentro da VM, instale Git, OpenSSL e Docker Engine com o plugin Compose seguindo
a [documentação oficial para Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
Docker Desktop não é necessário dentro do Linux. Verifique:

~~~bash
sudo docker version
sudo docker compose version
~~~

Clone o repositório privado dentro do disco Linux (autentique com sua conta,
sem gravar token na URL), selecionando staging:

~~~bash
git clone --branch staging --single-branch https://github.com/EasySlotting/EasySlotting.git
cd EasySlotting
hostname -I
~~~

Os arquivos desta configuração precisam estar publicados na branch remota para
o clone recebê-los. Se ainda estiverem apenas locais, transfira as alterações
revisadas ou publique o commit antes de clonar.

## Criar a configuração privada na VM

Na raiz do projeto, substitua o IP abaixo pelo IPv4 LAN da VM:

~~~bash
bash scripts/prepare-staging.sh 192.168.1.50
~~~

O script gera backend/.env.staging com permissão 600, segredos independentes,
senha de banco e senha de administrador aleatórias. Não imprime credenciais e
recusa sobrescrever um arquivo existente. Esse arquivo está ignorado pelo Git
e pelo build Docker. Consulte as credenciais somente no arquivo privado da VM.

O script configura o HTTPS, os hosts Rails, as origens CORS e a publicação da
porta 8443 para o mesmo IP. Mantenha esse IP estável. Se ele mudar, atualize juntos
STAGING_HOST, STAGING_BIND_ADDRESS, FRONTEND_URL, API_URL, ALLOWED_HOSTS e
ALLOWED_ORIGINS e recrie os containers. Não regenere as senhas de um banco
existente: trocar DB_PASSWORD no arquivo não altera a senha dentro do PostgreSQL.

Para um arquivo já existente, ajuste essas seis variáveis manualmente. O .env
de desenvolvimento não é alterado. Rails production não carrega .env sozinho:
o Compose injeta explicitamente backend/.env.staging.

## Iniciar e acessar pelo Windows

~~~bash
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml config --quiet
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml up -d --build
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml ps --all
~~~

Abra https://192.168.1.50:8443 no Windows (usando o IP real). O Compose espera
PostgreSQL saudável, executa db:prepare e inicia backend, worker e frontend.
O serviço prepare deve terminar com código 0. O banco começa separado e vazio.
O bootstrap cria o plano mensal e o administrador indicado no arquivo privado;
não apaga dados existentes e não usa os seeds de demonstração.

Depois do primeiro acesso, pode remover BOOTSTRAP_ADMIN_EMAIL e
BOOTSTRAP_ADMIN_PASSWORD do arquivo e recriar web/worker para retirar as
credenciais de seus ambientes. A conta criada permanece no banco.

A aplicação publica somente 8443 no IP escolhido. PostgreSQL, Rails e SMTP
ficam na rede interna Docker. Mailpit publica 8025 apenas no loopback Linux.
Para ver os e-mails capturados no navegador Windows, abra um túnel PowerShell:

~~~powershell
ssh -N -L 8025:127.0.0.1:8025 usuario@192.168.1.50
~~~

Mantenha o túnel aberto e acesse http://localhost:8025. E-mails não são enviados
a destinatários reais. Acesso SSH precisa estar habilitado na VM.
Restrinja o acesso à rede local; portas Docker publicadas exigem regras próprias
e não devem depender somente do UFW, conforme a documentação Docker.

## Confiar no HTTPS local

Caddy gera uma autoridade certificadora privada de staging. Depois de subir:

~~~bash
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml cp frontend:/data/caddy/pki/authorities/local/root.crt staging-root.crt
~~~

Copie somente esse certificado público para o Windows:

~~~powershell
scp usuario@192.168.1.50:~/EasySlotting/staging-root.crt .
~~~

Ajuste o caminho se clonou em outro diretório. Importe staging-root.crt nas
Autoridades de Certificação Raiz Confiáveis do usuário Windows (certmgr.msc).
Não exporte root.key. O certificado exportado é ignorado no Git. Certificados
e chave interna persistem no volume Caddy. Confira a origem do certificado antes
de confiar nele. Esta configuração não usa certificado público de domínio.

## Atualizar e manter os dados

~~~bash
git pull --ff-only origin staging
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml up -d --build --force-recreate
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml logs --tail=100 prepare web worker frontend
~~~

A recriação executa a preparação do banco para aplicar novas migrações. Faça
backup antes de alterações de schema. Não execute seeds de development aqui.
Os serviços contínuos usam restart: unless-stopped; habilite Docker na
inicialização do Linux para que os containers voltem após reiniciar a VM.

~~~bash
sudo systemctl enable --now docker
sudo docker compose --env-file backend/.env.staging -f compose.staging.yaml down
~~~

Down para os serviços e preserva os volumes de banco, uploads, e-mails e
certificados. Não use down -v para preservar os dados. Os volumes da VM não são
um backup: copie banco e uploads para um armazenamento separado periodicamente.

## Limites e validação

A configuração prepara homologação em VM local por IP, sem publicar na internet.
Para uma VPS pública, configure domínio e certificado público e reveja portas,
captura de e-mails, backups e credenciais antes de expor o serviço.
As tags das imagens são por versão principal; fixe versões/digests após validar.

Os testes Rails e o build frontend da preparação anterior passaram. As alterações
para Linux foram verificadas estaticamente e o gerador foi exercitado em diretório
temporário. Docker não está disponível nesta máquina Windows; o build das imagens,
a inicialização conjunta e o acesso HTTPS precisam ser validados na VM.
