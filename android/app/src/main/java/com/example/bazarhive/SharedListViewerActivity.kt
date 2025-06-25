package com.example.bazarhive

import android.os.Bundle
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ktx.firestore
import com.google.firebase.ktx.Firebase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale

class SharedListViewerActivity : AppCompatActivity() {
    private lateinit var messageTextView: TextView
    private lateinit var progressBar: ProgressBar
    private val db = Firebase.firestore
    private val numberFormat = NumberFormat.getNumberInstance(Locale("bn", "BD"))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_shared_list_viewer)

        messageTextView = findViewById(R.id.messageTextView)
        progressBar = findViewById(R.id.progressBar)

        // Get the list ID from the intent
        val listId = intent.data?.getQueryParameter("id")
        if (listId != null) {
            fetchSharedList(listId)
        } else {
            showError("Invalid list ID")
        }
    }

    private fun fetchSharedList(listId: String) {
        lifecycleScope.launch {
            try {
                showLoading(true)
                
                // Fetch document from Firestore
                val document = withContext(Dispatchers.IO) {
                    db.collection("shared_lists")
                        .document(listId)
                        .get()
                        .await()
                }

                if (document.exists()) {
                    // Parse document data
                    val ownerName = document.getString("ownerName") ?: "Unknown"
                    val items = document.get("items") as? Map<String, Map<String, Any>> ?: emptyMap()
                    
                    // Build the formatted message
                    val messageBuilder = StringBuilder()
                    messageBuilder.append("Shopping List from $ownerName\n\n")

                    var totalPriceSum = 0.0
                    
                    // Format each item
                    items.forEach { (itemCode, itemData) ->
                        val quantity = (itemData["quantity"] as? Number)?.toDouble() ?: 0.0
                        val unit = itemData["unit"] as? String ?: ""
                        val unitPrice = (itemData["unitPrice"] as? Number)?.toDouble() ?: 0.0
                        val totalPrice = (itemData["totalPrice"] as? Number)?.toDouble() ?: 0.0
                        
                        totalPriceSum += totalPrice
                        
                        messageBuilder.append(
                            "$itemCode: ${numberFormat.format(quantity)} $unit × ৳${numberFormat.format(unitPrice)} = ৳${numberFormat.format(totalPrice)}\n"
                        )
                    }
                    
                    messageBuilder.append("\nTotal: ৳${numberFormat.format(totalPriceSum)}\n\n")
                    messageBuilder.append("Import this list in BazarHive: https://bazarhive-a4bf2.web.app/redirect.html?id=$listId")
                    
                    showMessage(messageBuilder.toString())
                } else {
                    showError("Shared list not found")
                }
            } catch (e: Exception) {
                showError("Error loading shared list: ${e.message}")
            } finally {
                showLoading(false)
            }
        }
    }

    private fun showMessage(message: String) {
        messageTextView.text = message
    }

    private fun showError(error: String) {
        messageTextView.text = error
    }

    private fun showLoading(show: Boolean) {
        progressBar.visibility = if (show) View.VISIBLE else View.GONE
        messageTextView.visibility = if (show) View.GONE else View.VISIBLE
    }
}
