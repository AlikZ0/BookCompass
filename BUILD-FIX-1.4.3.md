# BookCompass 1.4.3 — исправление сборки после редизайна

## Ошибки из приложенного GitHub Actions лога

- `AnnotationDetailView.swift:32`: ambiguous use of `toolbar(content:)`
- `ReaderView.swift:85`: cannot find `PDFPageViewer` in scope
- `ReaderView.swift:94`: cannot infer contextual base `.horizontal` (каскадная ошибка после отсутствия компонента PDF)
- `ReaderView.swift:426`: `ContentUnavailableView` доступен только с iOS 17, проект поддерживает iOS 16.
- В `AnnotationDetailView` также использовался `ContentUnavailableView`; его устранили профилактически.

## Решение

- Вернули `PDFPageViewer` из предыдущей версии 1.4.1, сохранив навигацию и PDF-подсветку.
- Создали отдельный `editToolbar: some ToolbarContent` для ясной типизации.
- Заменили использование API iOS 17 на обычные `VStack`, `Image`, `Text` для iOS 16.
- `project.yml`: версия 1.4.3, целевая iOS 16.0 оставлена.

## Проверка

Все Swift-файлы проверены командой `swiftc -frontend -parse`, а YAML — структурно.
Успешная сборка `xcodebuild archive` не подтверждена: в этой среде нет Xcode и iOS SDK.

## Как обновить

1. Распаковать патч и поместить содержимое в корень GitHub-репозитория, заменив совпадающие пути.
2. Сделать commit в ветку `main`.
3. Запустить новую сборку Actions и проверить, что шаг архивирования завершился без `error:`.
4. Только после успешной сборки скачать `BookCompass-unsigned-IPA`, подписать для iPhone.
5. Не удалять предыдущую версию приложения. Чтобы сохранить книги, прежний Bundle ID должен остаться прежним.
