sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  R fold<R>(
    R Function(T data) onSuccess,
    R Function(AppError error) onFailure,
  ) {
    if (this is Success<T>) {
      return onSuccess((this as Success<T>).data);
    } else {
      return onFailure((this as Failure<T>).error);
    }
  }

  Result<R> map<R>(R Function(T data) transform) {
    if (this is Success<T>) {
      return Success(transform((this as Success<T>).data));
    } else {
      return Failure<R>((this as Failure<T>).error);
    }
  }

  Result<T> mapError(AppError Function(AppError error) transform) {
    if (this is Success<T>) {
      return this;
    } else {
      return Failure<T>(transform((this as Failure<T>).error));
    }
  }
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final AppError error;
  const Failure(this.error);
}

sealed class AppError {
  final String message;
  final Object? cause;

  const AppError(this.message, [this.cause]);
}

class FileError extends AppError {
  const FileError(super.message, [super.cause]);
}

class PermissionError extends AppError {
  const PermissionError(super.message, [super.cause]);
}

class ArchiveError extends AppError {
  const ArchiveError(super.message, [super.cause]);
}

class PdfError extends AppError {
  const PdfError(super.message, [super.cause]);
}

class OfficeError extends AppError {
  const OfficeError(super.message, [super.cause]);
}

class UnsupportedFileError extends AppError {
  const UnsupportedFileError(super.message, [super.cause]);
}

class UnknownError extends AppError {
  const UnknownError(super.message, [super.cause]);
}
