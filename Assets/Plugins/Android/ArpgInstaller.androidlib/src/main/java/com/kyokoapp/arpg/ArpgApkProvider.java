package com.kyokoapp.arpg;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

/** Narrow, read-only content provider for the verified APK downloaded by ContentUpdater. */
public final class ArpgApkProvider extends ContentProvider {
    private static final String MIME_TYPE = "application/vnd.android.package-archive";
    private static final String APK_NAME = "Arpg.apk";

    private File getApkFile() {
        File root = getContext().getExternalFilesDir(null);
        if (root == null) root = getContext().getFilesDir();
        return new File(new File(root, "updates"), APK_NAME);
    }

    private boolean isApkUri(Uri uri) {
        if (uri == null) return false;
        java.util.List<String> segments = uri.getPathSegments();
        return segments.size() == 2
            && "apk".equals(segments.get(0))
            && APK_NAME.equals(segments.get(1));
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return isApkUri(uri) ? MIME_TYPE : null;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        if (!isApkUri(uri)) return null;
        File apk = getApkFile();
        String[] columns = projection != null
            ? projection
            : new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE };
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        Object[] row = new Object[columns.length];
        for (int i = 0; i < columns.length; i++) {
            if (OpenableColumns.DISPLAY_NAME.equals(columns[i])) row[i] = APK_NAME;
            else if (OpenableColumns.SIZE.equals(columns[i])) row[i] = apk.isFile() ? apk.length() : 0L;
            else row[i] = null;
        }
        cursor.addRow(row);
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!isApkUri(uri) || !"r".equals(mode))
            throw new FileNotFoundException("Only the read-only Arpg update APK is available.");
        File apk = getApkFile();
        if (!apk.isFile()) throw new FileNotFoundException("The update APK is not available.");
        return ParcelFileDescriptor.open(apk, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }
}
