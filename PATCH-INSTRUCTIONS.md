# Обновление BookVoice 1.3 → BookCompass 1.4

1. Сначала сохраните существующий код BookVoice 1.3 и локальные книги (по возможности экспортируйте резервную копию).
2. Из `BookCompass-1.4-update-only.zip` перенесите файлы **в корень того же репозитория**, сохранив пути `BookVoice/...`, `.github/workflows/...` и `project.yml`.
3. Убедитесь, что ваш ранее установленный Bundle ID сохранён в `project.yml`. В архиве стоит исходный `com.example.BookVoice`: если вы меняли его ради подписи, верните своё значение.
4. `BookVoice/Services/BookSpeechPlayer.swift` обновляется патчем точечно. Не удаляйте `SpeechDelegateProxy.swift`, `LockScreenPlayer.swift`, старые `BookVoice/Models/Book.swift` или assets.
5. Если в репозитории уже есть иной workflow `main.yml`, запускающий сборку BookVoice, отключите его, чтобы не создавать дублирующие CI-запуски.
6. Commit → Actions → **Build BookCompass for iPhone** → скачайте `BookCompass-unsigned-IPA` → подпишите IPA → установите поверх предыдущего приложения.
7. Проверьте прежние PDF, страницу чтения и раздел «Мои знания». Если что-то изменилось, используйте резервную копию и журнал Actions.

**Неподписанный IPA не готов к установке.** Архив не доказывает успешную компиляцию без лога Xcode.
