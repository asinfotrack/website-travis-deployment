cat test.txt

export VERSION_DATE=$(date +"%Y%m%d_%H%M%S")
export VERSION_UID=${VERSION_DATE}_${CI_COMMIT_SHA:0:8}
# backup db
echo "Backing up mysql"
mysqldump --user=$DB_USER --password=$DB_PASS --host=$DB_HOST --port=3306 --default-character-set=utf8 --skip-triggers --single-transaction $DB_NAME > ${VERSION_DATE}_backup_before.sql
zip -q -9 ${VERSION_DATE}_backup_before.zip ${VERSION_DATE}_backup_before.sql
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/mysqlbk
scp -p22 ${VERSION_DATE}_backup_before.zip  $SSH_USER@$SSH_HOST:$ROOT_DIR/mysqlbk/${VERSION_DATE}_backup_before.zip
rm ${VERSION_DATE}_backup_before.sql
rm ${VERSION_DATE}_backup_before.zip
#upload
echo "Uploading data to server"
zip -q -r $VERSION_UID.zip . -x "./dev_node_modules/*"
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/releases
scp -p22 $VERSION_UID.zip  $SSH_USER@$SSH_HOST:$ROOT_DIR/releases/$VERSION_UID.zip
ssh -p22 $SSH_USER@$SSH_HOST unzip -qq $ROOT_DIR/releases/$VERSION_UID.zip -d $ROOT_DIR/releases/$VERSION_UID
ssh -p22 $SSH_USER@$SSH_HOST rm $ROOT_DIR/releases/$VERSION_UID.zip
rm $VERSION_UID.zip
#remove runtime
echo "linking runtime"
ssh -p22 $SSH_USER@$SSH_HOST rm -r $ROOT_DIR/releases/$VERSION_UID/backend/runtime || true
ssh -p22 $SSH_USER@$SSH_HOST rm -r $ROOT_DIR/releases/$VERSION_UID/frontend/runtime || true
ssh -p22 $SSH_USER@$SSH_HOST rm -r $ROOT_DIR/releases/$VERSION_UID/console/runtime || true
ssh -p22 $SSH_USER@$SSH_HOST rm -r $ROOT_DIR/releases/$VERSION_UID/common/runtime || true
#runtime directories
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/runtime/runtime_backend
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/runtime/runtime_frontend
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/runtime/runtime_console
ssh -p22 $SSH_USER@$SSH_HOST mkdir -p $ROOT_DIR/runtime/runtime_common
#runtime links
ssh -p22 $SSH_USER@$SSH_HOST ln -s $ROOT_DIR/runtime/runtime_backend $ROOT_DIR/releases/$VERSION_UID/backend/runtime
ssh -p22 $SSH_USER@$SSH_HOST ln -s $ROOT_DIR/runtime/runtime_frontend $ROOT_DIR/releases/$VERSION_UID/frontend/runtime
ssh -p22 $SSH_USER@$SSH_HOST ln -s $ROOT_DIR/runtime/runtime_console $ROOT_DIR/releases/$VERSION_UID/console/runtime
ssh -p22 $SSH_USER@$SSH_HOST ln -s $ROOT_DIR/runtime/runtime_common $ROOT_DIR/releases/$VERSION_UID/common/runtime
#permissions
ssh -p22 $SSH_USER@$SSH_HOST "find $ROOT_DIR/releases/$VERSION_UID/ -type d -exec chmod 755 {} \;"
ssh -p22 $SSH_USER@$SSH_HOST "find $ROOT_DIR/releases/$VERSION_UID/ -type f -exec chmod 644 {} \;"
#relink current
echo "relinking current"
ssh -p22 $SSH_USER@$SSH_HOST rm $ROOT_DIR/current || true
ssh -p22 $SSH_USER@$SSH_HOST ln -s $ROOT_DIR/releases/$VERSION_UID $ROOT_DIR/current
#rename old directory for cache bust
echo "cache busting"
ssh -p22 $SSH_USER@$SSH_HOST "find $ROOT_DIR/releases/ -type d -maxdepth 1 -mindepth 1 ! -name $VERSION_UID ! -name \"_*\" -execdir sh -c 'mv \$1 _\${1#./}' x {} \;"
#keep only last 10 releases (current + 9 old)
echo "cleanup"
ssh -p22 $SSH_USER@$SSH_HOST "ls -dt $ROOT_DIR/releases/_*/ | tail -n +10 | xargs -r rm -rf"
ssh -p22 $SSH_USER@$SSH_HOST "ls -dt $ROOT_DIR/mysqlbk/* | tail -n +11 | xargs -r rm"
#migrate
echo "migrating"
ssh -p22 $SSH_USER@$SSH_HOST $PHP_PATH $ROOT_DIR/current/yii migrate --interactive=0
curl -I -k $CACHE_BUST_URL